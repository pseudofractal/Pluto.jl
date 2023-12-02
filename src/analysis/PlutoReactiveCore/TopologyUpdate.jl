import ExpressionExplorer
import .ExpressionExplorerExtras
import ExpressionExplorer: SymbolsState, FunctionNameSignaturePair


"Return a copy of `old_topology`, but with recomputed results from `cells` taken into account."
function updated_topology(old_topology::NotebookTopology{C}, all_cells, updated_cells, get_code_str::Function, get_code_expr::Function) where C <: AbstractCell
	
	updated_codes = Dict{C,ExprAnalysisCache}()
	updated_nodes = Dict{C,ReactiveNode}()
	
	for cell in updated_cells
		# TODO this needs to be extracted somehow

		old_code = old_topology.codes[cell]
		new_code = get_code_str(cell)
		new_parsedcode = get_code_str(cell)
		(; parsedcode, needs_update) = get_parsedcode(cell; old_code)
		
		if old_code.code !== cell.code
			new_code = updated_codes[cell] = ExprAnalysisCache(cell, parsedcode)
			new_reactive_node = ExpressionExplorer.compute_reactive_node(ExpressionExplorerExtras.pretransform_pluto(new_code.parsedcode))

			updated_nodes[cell] = new_reactive_node
		elseif old_code.forced_expr_id !== nothing
			# reset computer code
			updated_codes[cell] = ExprAnalysisCache(old_code; forced_expr_id=nothing, function_wrapped=false)
		end
	end
	
	
	old_cells = all_cells(old_topology)
	removed_cells = setdiff(old_cells, all_cells)
	if isempty(removed_cells)
		# We can keep identity
		new_codes = merge(old_topology.codes, updated_codes)
		new_nodes = merge(old_topology.nodes, updated_nodes)
	else
		new_codes = merge(setdiffkeys(old_topology.codes, removed_cells), updated_codes)
		new_nodes = merge(setdiffkeys(old_topology.nodes, removed_cells), updated_nodes)
	end

	new_unresolved_set = setdiff!(
		union!(
			Set{C}(),
			# all cells that were unresolved before, and did not change code...
			Iterators.filter(old_topology.unresolved_cells) do c
				!haskey(updated_nodes, c)
			end,
			# ...plus all cells that changed, and now use a macrocall...
			Iterators.filter(updated_cells) do c
				!isempty(new_nodes[c].macrocalls)
			end,
		),
		# ...minus cells that were removed.
		removed_cells,
	)

	new_disabled_set = setdiff!(
		union!(
			Set{C}(),
			# all cells that were disabled before...
			old_topology.disabled_cells,
			# ...plus all cells that changed...
			updated_cells,
		),
		# ...minus cells that changed and are not disabled.
		Iterators.filter(!is_disabled, updated_cells),
	)

	unresolved_cells = if new_unresolved_set == old_topology.unresolved_cells
		old_topology.unresolved_cells
	else
		ImmutableSet(new_unresolved_set; skip_copy=true)
	end

	disabled_cells = if new_disabled_set == old_topology.disabled_cells
		old_topology.disabled_cells
	else
		ImmutableSet(new_disabled_set; skip_copy=true)
	end

	cell_order = if old_cells == all_cells
		old_topology.cell_order
	else
		ImmutableVector(all_cells) # makes a copy
	end
	
	NotebookTopology{C}(;
		nodes=new_nodes,
		codes=new_codes,
		unresolved_cells, 
        disabled_cells,
		cell_order,
	)
end
