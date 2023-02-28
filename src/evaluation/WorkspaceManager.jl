module WorkspaceManager
import UUIDs: UUID, uuid1
import ..Pluto
import ..Pluto: Configuration, Notebook, Cell, ProcessStatus, ServerSession, ExpressionExplorer, pluto_filename, Token, withtoken, tamepath, project_relative_path, putnotebookupdates!, UpdateMessage
import ..Pluto.Status
import ..Pluto.PkgCompat
import ..Configuration: CompilerOptions, _merge_notebook_compiler_options, _convert_to_flags
import ..Pluto.ExpressionExplorer: FunctionName
import ..PlutoRunner
import Distributed

"""
Contains the Julia process (in the sense of `Distributed.addprocs`) to evaluate code in.
Each notebook gets at most one `Workspace` at any time, but it can also have no `Workspace`
(it cannot `eval` code in this case).
"""
Base.@kwdef mutable struct Workspace
    pid::Integer
    notebook_id::UUID
    discarded::Bool=false
    remote_log_channel::Distributed.RemoteChannel
    module_name::Symbol
    dowork_token::Token=Token()
    nbpkg_was_active::Bool=false
    is_offline_renderer::Bool=false
    original_LOAD_PATH::Vector{String}=String[]
    original_ACTIVE_PROJECT::Union{Nothing,String}=nothing
end

const SN = Tuple{ServerSession, Notebook}

const active_workspaces = Dict{UUID,Task}()

"Set of notebook IDs that we will never make a process for again."
const discarded_workspaces = Set{UUID}()

const Distributed_expr = quote
    Base.loaded_modules[Base.PkgId(Base.UUID("8ba89e20-285c-5b6f-9357-94700520ee1b"), "Distributed")]
end

"These expressions get evaluated whenever a new `Workspace` process is created."
function process_preamble()
    quote
        Base.exit_on_sigint(false)
        include($(project_relative_path(joinpath("src", "runner"), "Loader.jl")))
        ENV["GKSwstype"] = "nul"
        ENV["JULIA_REVISE_WORKER_ONLY"] = "1"
    end
end

"Create a workspace for the notebook, optionally in the main process."
function make_workspace((session, notebook)::SN; is_offline_renderer::Bool=false)::Workspace
    workspace_business = is_offline_renderer ? Status.Business(name=:gobble) : Status.report_business_started!(notebook.status_tree, :workspace)
    create_status = Status.report_business_started!(workspace_business, :create_process)
    Status.report_business_planned!(workspace_business, :init_process)
    
    is_offline_renderer || (notebook.process_status = ProcessStatus.starting)

    use_distributed = !is_offline_renderer && session.options.evaluation.workspace_use_distributed

    pid = if use_distributed
        @debug "Creating workspace process" notebook.path length(notebook.cells)
        create_workspaceprocess(; 
            compiler_options=_merge_notebook_compiler_options(notebook, session.options.compiler),
            status=create_status,
        )
    else
        pid = Distributed.myid()
        if !(isdefined(Main, :PlutoRunner) && Main.PlutoRunner isa Module)
            # Make PlutoRunner available in Main, right now it's only defined inside this Pluto module.
            @eval Main begin
                PlutoRunner = $(PlutoRunner)
            end
        end
        pid
    end
    
    Status.report_business_finished!(workspace_business, :create_process)
    init_status = Status.report_business_started!(workspace_business, :init_process)
    Status.report_business_started!(init_status, Symbol(1))
    Status.report_business_planned!(init_status, Symbol(2))
    Status.report_business_planned!(init_status, Symbol(3))
    Status.report_business_planned!(init_status, Symbol(4))

    Distributed.remotecall_eval(Main, [pid], session.options.evaluation.workspace_custom_startup_expr)

    Distributed.remotecall_eval(Main, [pid], quote
        PlutoRunner.notebook_id[] = $(notebook.notebook_id)
    end)

    remote_log_channel = Core.eval(Main, quote
        $(Distributed).RemoteChannel(() -> eval(quote
            channel = Channel{Any}(10)
            Main.PlutoRunner.setup_plutologger(
                $($(notebook.notebook_id)), 
                channel,
            )
            channel
        end), $pid)
    end)

    run_channel = Core.eval(Main, quote
        $(Distributed).RemoteChannel(() -> eval(:(Main.PlutoRunner.run_channel)), $pid)
    end)

    module_name = create_emptyworkspacemodule(pid)

    original_LOAD_PATH, original_ACTIVE_PROJECT = Distributed.remotecall_eval(Main, pid, :(Base.LOAD_PATH, Base.ACTIVE_PROJECT[]))

    workspace = Workspace(;
        pid,
        notebook_id=notebook.notebook_id,
        remote_log_channel,
        module_name,
        original_LOAD_PATH,
        original_ACTIVE_PROJECT,
        is_offline_renderer,
    )
    
    
    Status.report_business_finished!(init_status, Symbol(1))
    Status.report_business_started!(init_status, Symbol(2))

    @async start_relaying_logs((session, notebook), remote_log_channel)
    @async start_relaying_self_updates((session, notebook), run_channel)
    cd_workspace(workspace, notebook.path)
    
    Status.report_business_finished!(init_status, Symbol(2))
    Status.report_business_started!(init_status, Symbol(3))
    
    use_nbpkg_environment((session, notebook), workspace)
    
    Status.report_business_finished!(init_status, Symbol(3))
    Status.report_business_started!(init_status, Symbol(4))
    
    # TODO: precompile 1+1 with display
    # sleep(3)
    eval_format_fetch_in_workspace(workspace, Expr(:toplevel, LineNumberNode(-1), :(1+1)), uuid1())
    
    Status.report_business_finished!(init_status, Symbol(4))
    Status.report_business_finished!(workspace_business, :init_process)
    Status.report_business_finished!(workspace_business)

    is_offline_renderer || if notebook.process_status == ProcessStatus.starting
        notebook.process_status = ProcessStatus.ready
    end
    return workspace
end

function use_nbpkg_environment((session, notebook)::SN, workspace=nothing)
    enabled = notebook.nbpkg_ctx !== nothing
    workspace.nbpkg_was_active == enabled && return

    workspace = workspace !== nothing ? workspace : get_workspace((session, notebook))
    workspace.discarded && return

    workspace.nbpkg_was_active = enabled
    if workspace.pid != Distributed.myid()
        new_LP = enabled ? ["@", "@stdlib"] : workspace.original_LOAD_PATH
        new_AP = enabled ? PkgCompat.env_dir(notebook.nbpkg_ctx) : workspace.original_ACTIVE_PROJECT

        Distributed.remotecall_eval(Main, [workspace.pid], quote
            copy!(LOAD_PATH, $(new_LP))
            Base.ACTIVE_PROJECT[] = $(new_AP)
        end)
    else
        # TODO
    end
end

function start_relaying_self_updates((session, notebook)::SN, run_channel::Distributed.RemoteChannel)
    while true
        try
            next_run_uuid = take!(run_channel)

            cell_to_run = notebook.cells_dict[next_run_uuid]
            Pluto.run_reactive!(session, notebook, notebook.topology, notebook.topology, Cell[cell_to_run]; user_requested_run=false)
        catch e
            if !isopen(run_channel)
                break
            end
            @error "Failed to relay self-update" exception=(e, catch_backtrace())
        end
    end
end

function start_relaying_logs((session, notebook)::SN, log_channel::Distributed.RemoteChannel)
    update_throttled, flush_throttled = Pluto.throttled(0.1) do
        Pluto.send_notebook_changes!(Pluto.ClientRequest(; session, notebook))
    end

    while true
        try
            next_log::Dict{String,Any} = take!(log_channel)

            fn = next_log["file"]
            match = findfirst("#==#", fn)

            # Show the log at the currently running cell, which is given by
            running_cell_id = next_log["cell_id"]::UUID

            # Some logs originate from outside of the running code, through function calls. Some code here to deal with that:
            begin
                source_cell_id = if match !== nothing
                    # The log originated from within the notebook
                    UUID(fn[match[end]+1:end])
                else
                    # The log originated from a function call defined outside of the notebook.
                    # Show the log at the currently running cell, at "line -1", i.e. without line info.
                    next_log["line"] = -1
                    running_cell_id
                end

                if running_cell_id != source_cell_id
                    # The log originated from a function in another cell of the notebook
                    # Show the log at the currently running cell, at "line -1", i.e. without line info.
                    next_log["line"] = -1
                end
            end

            source_cell = get(notebook.cells_dict, source_cell_id, nothing)
            running_cell = get(notebook.cells_dict, running_cell_id, nothing)

            display_cell = if running_cell === nothing || (source_cell !== nothing && source_cell.output.has_pluto_hook_features)
                source_cell
            else
                running_cell
            end

            @assert !isnothing(display_cell)

            maybe_max_log = findfirst(((key, _),) -> key == "maxlog", next_log["kwargs"])
            if maybe_max_log !== nothing
                n_logs = count(log -> log["id"] == next_log["id"], display_cell.logs)
                try
                    max_log = parse(Int, next_log["kwargs"][maybe_max_log][2] |> first)

                    # Don't include maxlog in the log-message, in line
                    # with how Julia handles it.
                    deleteat!(next_log["kwargs"], maybe_max_log)

                    # Don't show message with id more than max_log times
                    if max_log isa Int && n_logs >= max_log
                        continue
                    end
                catch
                end
            end

            push!(display_cell.logs, next_log)
            Pluto.@asynclog update_throttled()
        catch e
            if !isopen(log_channel)
                break
            end
            @error "Failed to relay log" exception=(e, catch_backtrace())
        end
    end
end

"Call `cd(\$path)` inside the workspace. This is done when creating a workspace, and whenever the notebook changes path."
function cd_workspace(workspace, path::AbstractString)
    eval_in_workspace(workspace, quote
        cd(dirname($path))
    end)
end

"Create a new empty workspace. Return the `(old, new)` workspace names as a tuple of `Symbol`s."
function bump_workspace_module(session_notebook::SN)
    workspace = get_workspace(session_notebook)
    old_name = workspace.module_name
    new_name = workspace.module_name = create_emptyworkspacemodule(workspace.pid)

    old_name, new_name
end

function get_bond_names(session_notebook::SN, cell_id)
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, workspace.pid, quote
        PlutoRunner.get_bond_names($cell_id)
    end)
end

function possible_bond_values(session_notebook::SN, n::Symbol; get_length::Bool=false)
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, workspace.pid, quote
        PlutoRunner.possible_bond_values($(QuoteNode(n)); get_length=$(get_length))
    end)
end

function create_emptyworkspacemodule(pid::Integer)::Symbol
    Distributed.remotecall_eval(Main, pid, quote
        PlutoRunner.increment_current_module()
    end)
end

# NOTE: this function only start a worker process using given
# compiler options, it does not resolve paths for notebooks
# compiler configurations passed to it should be resolved before this
function create_workspaceprocess(; compiler_options=CompilerOptions(), status::Status.Business=Business())::Integer
    
    Status.report_business_started!(status, Symbol(1))
    Status.report_business_planned!(status, Symbol(2))
    # run on proc 1 in case Pluto is being used inside a notebook process
    # Workaround for "only process 1 can add/remove workers"
    pid = Distributed.remotecall_eval(Main, 1, quote
        $(Distributed_expr).addprocs(1; exeflags=$(_convert_to_flags(compiler_options))) |> first
    end)
    
    Status.report_business_finished!(status, Symbol(1))
    Status.report_business_started!(status, Symbol(2))

    Distributed.remotecall_eval(Main, [pid], process_preamble())

    # so that we NEVER break the workspace with an interrupt 🤕
    @async Distributed.remotecall_eval(Main, [pid], quote
        while true
            try
                wait()
            catch end
        end
    end)
    
    Status.report_business_finished!(status)

    pid
end

"""
Return the `Workspace` of `notebook`; will be created if none exists yet.

If `allow_creation=false`, then `nothing` is returned if no workspace exists, instead of creating one.
"""
function get_workspace(session_notebook::SN; allow_creation::Bool=true)::Union{Nothing,Workspace}
    session, notebook = session_notebook
    if notebook.notebook_id in discarded_workspaces
        @debug "This should not happen" notebook.process_status
        error("Cannot run code in this notebook: it has already shut down.")
    end

    task = if !allow_creation
        get(active_workspaces, notebook.notebook_id, nothing)
    else
        get!(active_workspaces, notebook.notebook_id) do
            Task(() -> make_workspace(session_notebook))
        end
    end

    isnothing(task) && return nothing
    istaskstarted(task) || schedule(task)
    fetch(task)
end
get_workspace(workspace::Workspace; kwargs...)::Workspace = workspace

"Try our best to delete the workspace. `Workspace` will have its worker process terminated."
function unmake_workspace(session_notebook::SN; async::Bool=false, verbose::Bool=true, allow_restart::Bool=true)
    session, notebook = session_notebook
    workspace = get_workspace(session_notebook; allow_creation=false)
    workspace === nothing && return
    workspace.discarded = true
    allow_restart || push!(discarded_workspaces, notebook.notebook_id)

    if workspace.pid != Distributed.myid()
        filter!(p -> fetch(p.second).pid != workspace.pid, active_workspaces)
        t = @async begin
            interrupt_workspace(workspace; verbose=false)
            # run on proc 1 in case Pluto is being used inside a notebook process
            # Workaround for "only process 1 can add/remove workers"
            Distributed.remotecall_eval(Main, 1, quote
                $(Distributed_expr).rmprocs($(workspace.pid))
            end)
        end
        async || wait(t)
    else
        if !isready(workspace.dowork_token)
            @error "Cannot unmake a workspace running inside the same process: the notebook is still running."
        elseif verbose
            @warn "Cannot unmake a workspace running inside the same process: the notebook might still be running. If you are sure that your code is not running the notebook async, then you can use the `verbose=false` keyword argument to disable this message."
        end
    end
    nothing
end

function distributed_exception_result(ex::Base.IOError, workspace::Workspace)
    (
        output_formatted=PlutoRunner.format_output(CapturedException(ex, [])),
        errored=true,
        interrupted=true,
        process_exited=true && !workspace.discarded, # don't report a process exit if the workspace was discarded on purpose
        runtime=nothing,
        published_objects=Dict{String,Any}(),
        has_pluto_hook_features=false,
    )
end

function distributed_exception_result(exs::CompositeException, workspace::Workspace)
    ex = first(exs.exceptions)

    if ex isa Distributed.RemoteException &&
        ex.pid == workspace.pid &&
        ex.captured.ex isa InterruptException
        (
            output_formatted=PlutoRunner.format_output(CapturedException(InterruptException(), [])),
            errored=true,
            interrupted=true,
            process_exited=false,
            runtime=nothing,
            published_objects=Dict{String,Any}(),
            has_pluto_hook_features=false,
        )
    elseif ex isa Distributed.ProcessExitedException
        (
            output_formatted=PlutoRunner.format_output(CapturedException(exs, [])),
            errored=true,
            interrupted=true,
            process_exited=true && !workspace.discarded, # don't report a process exit if the workspace was discarded on purpose
            runtime=nothing,
            published_objects=Dict{String,Any}(),
            has_pluto_hook_features=false,
        )
    else
        @error "Unkown error during eval_format_fetch_in_workspace" ex
        (
            output_formatted=PlutoRunner.format_output(CapturedException(exs, [])),
            errored=true,
            interrupted=true,
            process_exited=false,
            runtime=nothing,
            published_objects=Dict{String,Any}(),
            has_pluto_hook_features=false,
        )
    end
end


"""
Evaluate expression inside the workspace - output is fetched and formatted,
errors are caught and formatted. Returns formatted output and error flags.

`expr` has to satisfy `ExpressionExplorer.is_toplevel_expr`.
"""
function eval_format_fetch_in_workspace(
    session_notebook::Union{SN,Workspace},
    expr::Expr,
    cell_id::UUID;
    ends_with_semicolon::Bool=false,
    function_wrapped_info::Union{Nothing,Tuple}=nothing,
    forced_expr_id::Union{PlutoRunner.ObjectID,Nothing}=nothing,
    known_published_objects::Vector{String}=String[],
    user_requested_run::Bool=true,
    capture_stdout::Bool=true
)::PlutoRunner.FormattedCellResult

    workspace = get_workspace(session_notebook)

    is_on_this_process = workspace.pid == Distributed.myid()

    # if multiple notebooks run on the same process, then we need to `cd` between the different notebook paths
    if session_notebook isa Tuple
        if is_on_this_process
            cd_workspace(workspace, session_notebook[2].path)
        end
        use_nbpkg_environment(session_notebook, workspace)
    end

    # Run the code 🏃

    # A try block (on this process) to catch an InterruptException
    take!(workspace.dowork_token)
    early_result = try
        # Use [pid] instead of pid to prevent fetching output
        Distributed.remotecall_eval(Main, [workspace.pid], quote
            PlutoRunner.run_expression(
                getfield(Main, $(QuoteNode(workspace.module_name))),
                $(QuoteNode(expr)),
                $(workspace.notebook_id),
                $cell_id,
                $function_wrapped_info,
                $forced_expr_id;
                user_requested_run=$user_requested_run,
                capture_stdout=$(capture_stdout && !is_on_this_process),
            )
        end)
        put!(workspace.dowork_token)
        nothing
    catch e
        # Don't use a `finally` because the token needs to be back asap for the interrupting code to pick it up.
        put!(workspace.dowork_token)
        distributed_exception_result(e, workspace)
    end

    if early_result === nothing
        format_fetch_in_workspace(workspace, cell_id, ends_with_semicolon, known_published_objects; capture_stdout)
    else
        early_result
    end
end

"Evaluate expression inside the workspace - output is not fetched, errors are rethrown. For internal use."
function eval_in_workspace(session_notebook::Union{SN,Workspace}, expr)
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, [workspace.pid], quote
        Core.eval($(workspace.module_name), $(QuoteNode(expr)))
    end)
    nothing
end

function format_fetch_in_workspace(
    session_notebook::Union{SN,Workspace},
    cell_id,
    ends_with_semicolon,
    known_published_objects::Vector{String}=String[],
    showmore_id::Union{PlutoRunner.ObjectDimPair,Nothing}=nothing;
    capture_stdout::Bool=true,
)::PlutoRunner.FormattedCellResult
    workspace = get_workspace(session_notebook)

    # Instead of fetching the output value (which might not make sense in our context,
    # since the user can define structs, types, functions, etc),
    # we format the cell output on the worker, and fetch the formatted output.
    withtoken(workspace.dowork_token) do
        try
            Distributed.remotecall_eval(Main, workspace.pid, quote
                PlutoRunner.formatted_result_of(
                    $(workspace.notebook_id),
                    $cell_id,
                    $ends_with_semicolon,
                    $known_published_objects,
                    $showmore_id,
                    getfield(Main, $(QuoteNode(workspace.module_name)));
                    capture_stdout=$capture_stdout,
                )
            end)
        catch e
            distributed_exception_result(CompositeException([e]), workspace)
        end
    end
end

function collect_soft_definitions(session_notebook::SN, modules::Set{Expr})
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, workspace.pid, quote
        PlutoRunner.collect_soft_definitions($(workspace.module_name), $modules)
    end)
end

function macroexpand_in_workspace(session_notebook::SN, macrocall, cell_id, module_name = nothing; capture_stdout::Bool=true)::Tuple{Bool, Any}
    workspace = get_workspace(session_notebook)
    module_name = module_name === nothing ? workspace.module_name : module_name

    Distributed.remotecall_eval(Main, workspace.pid, quote
        try
            (true, PlutoRunner.try_macroexpand($(module_name), $(workspace.notebook_id), $(cell_id), $(macrocall |> QuoteNode); capture_stdout=$(capture_stdout)))
        catch error
            # We have to be careful here, for example a thrown `MethodError()` will contain the called method and arguments.
            # which normally would be very useful for debugging, but we can't serialize it!
            # So we make sure we only serialize the exception we know about, and string-ify the others.
            if (error isa LoadError && error.error isa UndefVarError) || error isa UndefVarError
                (false, error)
            else
                (false, ErrorException(sprint(showerror, error)))
            end
        end
    end)
end

"Evaluate expression inside the workspace - output is returned. For internal use."
function eval_fetch_in_workspace(session_notebook::Union{SN,Workspace}, expr)
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, workspace.pid, quote
        Core.eval($(workspace.module_name), $(QuoteNode(expr)))
    end)
end

function do_reimports(session_notebook::Union{SN,Workspace}, module_imports_to_move::Set{Expr})
    workspace = get_workspace(session_notebook)

    Distributed.remotecall_eval(Main, [workspace.pid], quote
        PlutoRunner.do_reimports($(workspace.module_name), $module_imports_to_move)
    end)
end

"""
Move variables to a new module. Variables to be 'deleted' will not be moved to
the new module, making them unavailable.
"""
function move_vars(
    session_notebook::Union{SN,Workspace},
    old_workspace_name::Symbol,
    new_workspace_name::Union{Nothing,Symbol},
    to_delete::Set{Symbol},
    methods_to_delete::Set{Tuple{UUID,FunctionName}},
    module_imports_to_move::Set{Expr},
    invalidated_cell_uuids::Set{UUID},
    keep_registered::Set{Symbol}=Set{Symbol}();
    kwargs...
    )

    workspace = get_workspace(session_notebook)
    new_workspace_name = something(new_workspace_name, workspace.module_name)

    Distributed.remotecall_eval(Main, [workspace.pid], quote
        PlutoRunner.move_vars(
            $(QuoteNode(old_workspace_name)),
            $(QuoteNode(new_workspace_name)),
            $to_delete,
            $methods_to_delete,
            $module_imports_to_move,
            $invalidated_cell_uuids,
            $keep_registered,
        )
    end)
end

function move_vars(session_notebook::Union{SN,Workspace}, to_delete::Set{Symbol}, methods_to_delete::Set{Tuple{UUID,FunctionName}}, module_imports_to_move::Set{Expr}, invalidated_cell_uuids::Set{UUID}; kwargs...)
    move_vars(session_notebook, bump_workspace_module(session_notebook)..., to_delete, methods_to_delete, module_imports_to_move, invalidated_cell_uuids; kwargs...)
end

# TODO: delete me
@deprecate(
    delete_vars(args...; kwargs...),
    move_vars(args...; kwargs...)
)

"""
```julia
poll(query::Function, timeout::Real=Inf64, interval::Real=1/20)::Bool
```

Keep running your function `query()` in intervals until it returns `true`, or until `timeout` seconds have passed.

`poll` returns `true` if `query()` returned `true`. If `timeout` seconds have passed, `poll` returns `false`.

# Example
```julia
vals = [1,2,3]

@async for i in 1:5
    sleep(1)
    vals[3] = 99
end

poll(8 #= seconds =#) do
    vals[3] == 99
end # returns `true` (after 5 seconds)!

###

@async for i in 1:5
    sleep(1)
    vals[3] = 5678
end

poll(2 #= seconds =#) do
    vals[3] == 5678
end # returns `false` (after 2 seconds)!
```
"""
function poll(query::Function, timeout::Real=Inf64, interval::Real=1/20)
    start = time()
    while time() < start + timeout
        if query()
            return true
        end
        sleep(interval)
    end
    return false
end

"Force interrupt (SIGINT) a workspace, return whether successful"
function interrupt_workspace(session_notebook::Union{SN,Workspace}; verbose=true)::Bool
    workspace = get_workspace(session_notebook; allow_creation=false)

    if !(workspace isa Workspace)
        # verbose && @info "Can't interrupt this notebook: it is not running."
        return false
    end

    if poll(() -> isready(workspace.dowork_token), 2.0, 5/100)
        verbose && println("Cell finished, other cells cancelled!")
        return true
    end

    if Sys.iswindows()
        verbose && @warn "Unfortunately, stopping cells is currently not supported on Windows :(
        Maybe the Windows Subsystem for Linux is right for you:
        https://docs.microsoft.com/en-us/windows/wsl"
        return false
    end

    if workspace.pid == Distributed.myid()
        verbose && @warn """Cells in this workspace can't be stopped, because it is not running in a separate workspace. Use `ENV["PLUTO_WORKSPACE_USE_DISTRIBUTED"]` to control whether future workspaces are generated in a separate process."""
        return false
    end

    if isready(workspace.dowork_token)
        verbose && @info "Tried to stop idle workspace - ignoring."
        return true
    end

    # You can force kill a julia process by pressing Ctrl+C five times 🙃
    # But this is not very consistent, so we will just keep pressing Ctrl+C until the workspace isn't running anymore.
    # TODO: this will also kill "pending" evaluations, and any evaluations started within 100ms of the kill. A global "evaluation count" would fix this.
    # TODO: listen for the final words of the remote process on stdout/stderr: "Force throwing a SIGINT"
    try
        verbose && @info "Sending interrupt to process $(workspace.pid)"
        Distributed.interrupt(workspace.pid)

        if poll(() -> isready(workspace.dowork_token), 5.0, 5/100)
            verbose && println("Cell interrupted!")
            return true
        end

        verbose && println("Still running... starting sequence")
        while !isready(workspace.dowork_token)
            for _ in 1:5
                verbose && print(" 🔥 ")
                Distributed.interrupt(workspace.pid)
                sleep(0.18)
                if isready(workspace.dowork_token)
                    break
                end
            end
            sleep(1.5)
        end
        verbose && println()
        verbose && println("Cell interrupted!")
        true
    catch e
        if !(e isa KeyError)
            @warn "Interrupt failed for unknown reason"
            showerror(e, stacktrace(catch_backtrace()))
        end
        false
    end
end

end
