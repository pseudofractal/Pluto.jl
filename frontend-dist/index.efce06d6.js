var e="undefined"!=typeof globalThis?globalThis:"undefined"!=typeof self?self:"undefined"!=typeof window?window:"undefined"!=typeof global?global:{},t={},o={},n=e.parcelRequire94c2;null==n&&((n=function(e){if(e in t)return t[e].exports;if(e in o){var n=o[e];delete o[e];var a={id:e,exports:{}};return t[e]=a,n.call(a.exports,a,a.exports),a.exports}var r=new Error("Cannot find module '"+e+"'");throw r.code="MODULE_NOT_FOUND",r}).register=function(e,t){o[e]=t},e.parcelRequire94c2=n);var a=n("cNaMA");n("eS9BV");var r,l,i,s,c={};r=c,l="Welcome",i=()=>j,s=e=>j=e,Object.defineProperty(r,l,{get:i,set:s,enumerable:!0,configurable:!0}),n("9Ta4i");a=n("cNaMA"),a=n("cNaMA");var d=n("4zMEb");const u=async()=>{let e=await fetch("https://api.github.com/repos/fonsp/Pluto.jl/releases",{method:"GET",mode:"cors",cache:"no-cache",headers:{"Content-Type":"application/json"},redirect:"follow",referrerPolicy:"no-referrer"});return(await e.json()).reverse()};n("9Ta4i");a=n("cNaMA");var p=n("2ZZ1r");a=n("cNaMA");const h=e=>{const t=`${e}\n`.replace("\r\n","\n"),o=t.indexOf("### A Pluto.jl notebook ###"),n=t.match(/# ... ........-....-....-....-............/g),a=(null==n?void 0:n.length)??0;let r=t.indexOf("# ╔═╡ Cell order:")+17+1;for(let e=1;e<=a;e++)r=t.indexOf("\n",r+1)+1;return t.slice(o,r)},f=async e=>{var t;let o;if(console.log(e),(null===(t=((null==e?void 0:e.path)??(null==e?void 0:e.composedPath())).filter((e=>{var t;return null==e||null===(t=e.classList)||void 0===t?void 0:t.contains(".cm-editor")})))||void 0===t?void 0:t.length)>0)return;switch(e.type){case"paste":o=h(e.clipboardData.getData("text/plain"));break;case"dragstart":return void(e.dataTransfer.dropEffect="move");case"dragover":return void e.preventDefault();case"drop":e.preventDefault(),o=e.dataTransfer.types.includes("Files")?await(a=e.dataTransfer.files[0],new Promise(((e,t)=>{const{name:o,type:n}=a,r=new FileReader;r.onerror=()=>t("Failed to read file!"),r.onloadstart=()=>{},r.onprogress=({loaded:e,total:t})=>{},r.onload=()=>{},r.onloadend=()=>e({file:r.result,name:o,type:n}),r.readAsText(a)}))).then((({file:e})=>e)):h(await(n=e.dataTransfer.items[0],new Promise(((e,t)=>{try{n.getAsString((t=>{console.log(t),e(t)}))}catch(e){t(e)}}))))}var n,a;if(!o)return;document.body.classList.add("loading");const r=await fetch("./notebookupload",{method:"POST",body:o});if(r.ok)window.location.href=v(await r.text());else{let e=await r.blob();window.location.href=URL.createObjectURL(e)}},m=()=>(a.useEffect((()=>(document.addEventListener("paste",f),document.addEventListener("drop",f),document.addEventListener("dragstart",f),document.addEventListener("dragover",f),()=>{document.removeEventListener("paste",f),document.removeEventListener("drop",f),document.removeEventListener("dragstart",f),document.removeEventListener("dragover",f)}))),a.html`<span />`),g=e=>e.toLowerCase().normalize("NFD").replace(/[^a-z1-9]/g,""),b=({client:e,connected:t,CustomPicker:o,show_samples:n})=>{const r=o??{text:"Open from file",placeholder:"Enter path or URL..."};return a.html`<p>New session:</p>
        <${m} />
        <ul id="new">
            ${n&&a.html`<li>Open a <a href="sample">sample notebook</a></li>`}
            <li>Create a <a href="new">new notebook</a></li>
            <li>
                ${r.text}:
                <${p.FilePicker}
                    key=${r.placeholder}
                    client=${e}
                    value=""
                    on_submit=${async e=>{const t=await(async e=>{try{const t=new URL(e);if(!["http:","https:","ftp:","ftps:"].includes(t.protocol))throw"Not a web URL";if("gist.github.com"===t.host){console.log("Gist URL detected");const e=t.pathname.substring(1).split("/")[1],o=await(await fetch(`https://api.github.com/gists/${e}`,{headers:{Accept:"application/vnd.github.v3+json"}}).then((e=>e.ok?e:Promise.reject(e)))).json();console.log(o);const n=Object.values(o.files),a=n.find((e=>g("#file-"+e.filename)===g(t.hash)));return null!=a?{type:"url",path_or_url:a.raw_url}:{type:"url",path_or_url:n[0].raw_url}}return"github.com"===t.host&&t.searchParams.set("raw","true"),{type:"url",path_or_url:t.href}}catch(t){return'"'===e[e.length-1]&&'"'===e[0]&&(e=e.slice(1,-1)),{type:"path",path_or_url:e}}})(e);"path"===t.type?(document.body.classList.add("loading"),window.location.href=_(t.path_or_url)):confirm("Are you sure? This will download and run the file at\n\n"+t.path_or_url)&&(document.body.classList.add("loading"),window.location.href=w(t.path_or_url))}}
                    button_label="Open"
                    placeholder=${r.placeholder}
                />
            </li>
        </ul>`},_=e=>"open?"+new URLSearchParams({path:e}).toString(),w=e=>"open?"+new URLSearchParams({url:e}).toString(),v=e=>"edit?id="+e;var k=n("9Ta4i"),y=(a=n("cNaMA"),a=n("cNaMA"),n("aN0pg"));const $=(e,t=null)=>({transitioning:!1,notebook_id:t,path:e}),L=(e,t)=>e.split(/\/|\\/).slice(-t).join("/"),P=({client:e,connected:t,remote_notebooks:o,CustomRecent:n})=>{const[r,l]=a.useState(null),i=a.useRef(r);i.current=r;const s=(e,t)=>{l((o=>(null==o?void 0:o.map((o=>o.path==e?{...o,...t}:o)))??null))};a.useEffect((()=>{null!=e&&t&&e.send("get_all_notebooks",{},{}).then((({message:e})=>{const t=e.notebooks.map((e=>$(e.path,e.notebook_id))),o=E(),n=[...k.default.sortBy(t,[e=>k.default.findIndex([...o,...t],(t=>t.path===e.path))]),...k.default.differenceBy(o,t,(e=>e.path))];l(n),document.body.classList.remove("loading")}))}),[null!=e&&t]),a.useEffect((()=>{const e=o;if(null!=i.current){const t=[],o=i.current.map((o=>{let n=null;if(n=o.notebook_id?e.find((e=>e.notebook_id==o.notebook_id)):e.find((e=>e.path==o.path)),null==n)return $(o.path);{const e=$(n.path,n.notebook_id);return t.push(n),e}})),n=e.filter((e=>!t.includes(e))).map((e=>$(e.path,e.notebook_id)));l([...n,...o])}}),[o]);a.useEffect((()=>{document.body.classList.toggle("nosessions",!(null==r||r.length>0))}),[r]);const c=null==r?void 0:r.map((e=>e.path));let d=null==r?a.html`<li><em>Loading...</em></li>`:r.map((t=>{const o=null!=t.notebook_id;return a.html`<li
                      key=${t.path}
                      class=${y.cl({running:o,recent:!o,transitioning:t.transitioning})}
                  >
                      <button onclick=${()=>(t=>{if(t.transitioning)return;if(null!=t.notebook_id){if(null==e)return;confirm("Shut down notebook process?")&&(s(t.path,{running:!1,transitioning:!0}),e.send("shutdown_notebook",{keep_in_session:!1},{notebook_id:t.notebook_id},!1))}else s(t.path,{transitioning:!0}),fetch(_(t.path),{method:"GET"}).then((e=>{if(!e.redirected)throw new Error("file not found maybe? try opening the notebook directly")})).catch((e=>{console.error("Failed to start notebook in background"),console.error(e),s(t.path,{transitioning:!1,notebook_id:null})}))})(t)} title=${o?"Shut down notebook":"Start notebook in background"}>
                          <span></span>
                      </button>
                      <a
                          href=${o?v(t.notebook_id):_(t.path)}
                          title=${t.path}
                          onClick=${e=>{o||(document.body.classList.add("loading"),s(t.path,{transitioning:!0}))}}
                          >${((e,t)=>{let o=1;for(const n of t)if(n!==e)for(;L(e,o)===L(n,o);)o++;return L(e,o)})(t.path,c)}</a
                      >
                  </li>`}));return null==n?a.html`
            <p>Recent sessions:</p>
            <ul id="recent">
                ${d}
            </ul>
        `:a.html`<${n} cl=${y.cl} combined=${r} client=${e} recents=${d} />`},E=()=>{const e=localStorage.getItem("recent notebooks"),t=null!=e?JSON.parse(e):[];return(t instanceof Array?t:[]).map((e=>$(e)))},j=()=>{const[e,t]=a.useState([]),[o,n]=a.useState(!1),[r,l]=a.useState({show_samples:!0,CustomPicker:null,CustomRecent:null}),i=a.useRef({});a.useEffect((()=>{const e=n;d.create_pluto_connection({on_unrequested_update:({message:e,type:o})=>{"notebook_list"===o&&t(e.notebooks)},on_connection_status:e,on_reconnect:()=>!0}).then((async e=>{Object.assign(i.current,e),n(!0);try{const{default:t}=await import(e.session_options.server.injected_javascript_data_url),{custom_recent:o,custom_filepicker:n,show_samples:r=!0}=t({client:e,editor:void 0,imports:{preact:a}});l((e=>({...e,CustomRecent:o,CustomPicker:n,show_samples:r})))}catch(e){}(e=>{u().then((t=>{const o=e.version_info.pluto,n=t[t.length-1].tag_name;console.log(`Pluto version ${o}`);const a=t.findIndex((e=>e.tag_name===o));-1!==a&&t.slice(a+1).filter((e=>e.body.toLowerCase().includes("recommended update"))).length>0&&(console.log(`Newer version ${n} is available`),e.version_info.dismiss_update_notification||alert("A new version of Pluto.jl is available! 🎉\n\n    You have "+o+", the latest is "+n+'.\n\nYou can update Pluto.jl using the julia package manager:\n    import Pkg; Pkg.update("Pluto")\nAfterwards, exit Pluto.jl and restart julia.'))})).catch((()=>{}))})(e),e.send("completepath",{query:""},{})}))}),[]);const{show_samples:s,CustomRecent:c,CustomPicker:p}=r;return a.html`
        <${b} client=${i.current} connected=${o} CustomPicker=${p} show_samples=${s} />
        <br />
        <${P} client=${i.current} connected=${o} remote_notebooks=${e} CustomRecent=${c} />
    `};a.render(a.html`<${c.Welcome} />`,document.querySelector("main"));