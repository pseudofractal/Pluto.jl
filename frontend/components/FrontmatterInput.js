import { html, Component, useRef, useLayoutEffect, useState, useEffect } from "../imports/Preact.js"
import { has_ctrl_or_cmd_pressed } from "../common/KeyboardShortcuts.js"

import "https://cdn.jsdelivr.net/gh/fonsp/rebel-tag-input@1.0.4/lib/rebel-tag-input.mjs"

import dialogPolyfill from "https://cdn.jsdelivr.net/npm/dialog-polyfill@0.5.6/dist/dialog-polyfill.esm.min.js"

/**
 * @param {{
 *  remote_frontmatter: Record<String,any>,
 *  set_remote_frontmatter: (newval: Record<String,any>) => void,
 * }} props
 * */
export const FrontMatterInput = ({ remote_frontmatter, set_remote_frontmatter }) => {
    const [frontmatter, set_frontmatter] = useState(remote_frontmatter)

    useEffect(() => {
        set_frontmatter(remote_frontmatter)
    }, [remote_frontmatter])

    // useEffect(() => {
    //     console.log("New frontmatter:", frontmatter)
    // }, [frontmatter])

    const fm_setter = (key) => (value) => {
        set_frontmatter((fm) => ({ ...fm, [key]: value }))
    }

    const dialog_ref = useRef(/** @type {HTMLDialogElement} */ (null))
    useLayoutEffect(() => {
        dialogPolyfill.registerDialog(dialog_ref.current)
    })

    //@ts-ignore
    const open = () => dialog_ref.current.showModal()
    //@ts-ignore
    const close = () => dialog_ref.current.close()

    const cancel = () => {
        set_frontmatter(remote_frontmatter)
        close()
    }
    const submit = () => {
        set_remote_frontmatter(frontmatter)
        close()
    }

    useLayoutEffect(() => {
        open()
    }, [])

    useLayoutEffect(() => {
        const listener = (e) => {
            if (e.key === "Enter" && has_ctrl_or_cmd_pressed(e)) submit()
        }
        window.addEventListener("keydown", listener)
        return () => {
            window.removeEventListener("keydown", listener)
        }
    }, [])

    const frontmatter_with_defaults = {
        title: null,
        description: null,
        date: null,
        tags: [],
        license: null,
        ...frontmatter,
    }

    return html`<dialog ref=${dialog_ref} class="pluto-frontmatter">
        <h1>Frontmatter</h1>
        <p>
            If you are publishing this notebook on the web, you can set the parameters below to provide HTML metadata. This is useful for search engines and
            social media.
        </p>
        <div class="fm-table">
            ${Object.entries(frontmatter_with_defaults).map(([key, value]) => {
                let id = `fm-${key}`
                return html`
                    <label for=${id}>${key}</label>
                    <${Input} type=${field_type(key)} id=${id} value=${value} on_value=${fm_setter(key)} />
                    <button
                        class="deletefield"
                        onClick=${() => {
                            set_frontmatter((fm) => Object.fromEntries(Object.entries(fm).filter(([k]) => k !== key)))
                        }}
                    >
                        ⨯
                    </button>
                `
            })}
            <button
                class="addentry"
                onClick=${() => {
                    const fieldname = prompt("Field name:")
                    if (fieldname) {
                        set_frontmatter((fm) => ({ ...fm, [fieldname]: null }))
                    }
                }}
            >
                Add entry +
            </button>
        </div>

        <div class="final"><button onClick=${cancel}>Cancel</button><button onClick=${submit}>Save</button></div>
    </dialog>`
}

const field_type = (name) => (name === "tags" ? "tags" : name === "date" ? "date" : name === "license" ? "license" : "text")

const Input = ({ value, on_value, type, id }) => {
    const input_ref = useRef(/** @type {HTMLInputElement} */ (null))

    useLayoutEffect(() => {
        input_ref.current.value = value
    }, [input_ref.current, value])

    useLayoutEffect(() => {
        const listener = (e) => {
            on_value(input_ref.current.value)
        }

        input_ref.current.addEventListener("input", listener)
        return () => {
            input_ref.current.removeEventListener("input", listener)
        }
    }, [input_ref.current])

    return type === "tags"
        ? html`<rbl-tag-input id=${id} ref=${input_ref} />`
        : type === "license"
        ? LicenseInput({ ref: input_ref, id })
        : html`<input type=${type} id=${id} ref=${input_ref} />`
}

const licenses = ["AGPL-3.0", "GPL-3.0", "LGPL-3.0", "MPL-2.0", "Apache-2.0", "MIT", "BSL-1.0", "Unlicense"]

const LicenseInput = ({ ref, id }) => {
    return html`
        <input ref=${ref} id=${id} type="text" list="oss-licenses" />
        <datalist id="oss-licenses">${licenses.map((name) => html`<option>${name}</option>`)}</datalist>
    `
}
