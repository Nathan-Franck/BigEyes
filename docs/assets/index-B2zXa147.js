(async()=>{(function(){const t=document.createElement("link").relList;if(t&&t.supports&&t.supports("modulepreload"))return;for(const o of document.querySelectorAll('link[rel="modulepreload"]'))n(o);new MutationObserver(o=>{for(const _ of o)if(_.type==="childList")for(const i of _.addedNodes)i.tagName==="LINK"&&i.rel==="modulepreload"&&n(i)}).observe(document,{childList:!0,subtree:!0});function e(o){const _={};return o.integrity&&(_.integrity=o.integrity),o.referrerPolicy&&(_.referrerPolicy=o.referrerPolicy),o.crossOrigin==="use-credentials"?_.credentials="include":o.crossOrigin==="anonymous"?_.credentials="omit":_.credentials="same-origin",_}function n(o){if(o.ep)return;o.ep=!0;const _=e(o);fetch(o.href,_)}})();var $,b,pe,P,de,he,te,ne,re,oe,C={},me=[],Xe=/acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i,_e=Array.isArray;function F(t,e){for(var n in e)t[n]=e[n];return t}function ye(t){var e=t.parentNode;e&&e.removeChild(t)}function Oe(t,e,n){var o,_,i,a={};for(i in e)i=="key"?o=e[i]:i=="ref"?_=e[i]:a[i]=e[i];if(arguments.length>2&&(a.children=arguments.length>3?$.call(arguments,2):n),typeof t=="function"&&t.defaultProps!=null)for(i in t.defaultProps)a[i]===void 0&&(a[i]=t.defaultProps[i]);return W(t,a,o,_,null)}function W(t,e,n,o,_){var i={type:t,props:e,key:n,ref:o,__k:null,__:null,__b:0,__e:null,__d:void 0,__c:null,constructor:void 0,__v:_??++pe,__i:-1,__u:0};return _==null&&b.vnode!=null&&b.vnode(i),i}function M(t){return t.children}function X(t,e){this.props=t,this.context=e}function N(t,e){if(e==null)return t.__?N(t.__,t.__i+1):null;for(var n;e<t.__k.length;e++)if((n=t.__k[e])!=null&&n.__e!=null)return n.__e;return typeof t.type=="function"?N(t):null}function ge(t){var e,n;if((t=t.__)!=null&&t.__c!=null){for(t.__e=t.__c.base=null,e=0;e<t.__k.length;e++)if((n=t.__k[e])!=null&&n.__e!=null){t.__e=t.__c.base=n.__e;break}return ge(t)}}function ve(t){(!t.__d&&(t.__d=!0)&&P.push(t)&&!O.__r++||de!==b.debounceRendering)&&((de=b.debounceRendering)||he)(O)}function O(){var t,e,n,o,_,i,a,u;for(P.sort(te);t=P.shift();)t.__d&&(e=P.length,o=void 0,i=(_=(n=t).__v).__e,a=[],u=[],n.__P&&((o=F({},_)).__v=_.__v+1,b.vnode&&b.vnode(o),ie(n.__P,o,_,n.__n,n.__P.ownerSVGElement!==void 0,32&_.__u?[i]:null,a,i??N(_),!!(32&_.__u),u),o.__v=_.__v,o.__.__k[o.__i]=o,xe(a,o,u),o.__e!=i&&ge(o)),P.length>e&&P.sort(te));O.__r=0}function Ee(t,e,n,o,_,i,a,u,s,c,y){var l,g,r,f,d,p=o&&o.__k||me,h=e.length;for(n.__d=s,Ge(n,e,p),s=n.__d,l=0;l<h;l++)(r=n.__k[l])!=null&&typeof r!="boolean"&&typeof r!="function"&&(g=r.__i===-1?C:p[r.__i]||C,r.__i=l,ie(t,r,g,_,i,a,u,s,c,y),f=r.__e,r.ref&&g.ref!=r.ref&&(g.ref&&le(g.ref,null,r),y.push(r.ref,r.__c||f,r)),d==null&&f!=null&&(d=f),65536&r.__u||g.__k===r.__k?(s&&!s.isConnected&&(s=N(g)),s=be(r,s,t)):typeof r.type=="function"&&r.__d!==void 0?s=r.__d:f&&(s=f.nextSibling),r.__d=void 0,r.__u&=-196609);n.__d=s,n.__e=d}function Ge(t,e,n){var o,_,i,a,u,s=e.length,c=n.length,y=c,l=0;for(t.__k=[],o=0;o<s;o++)a=o+l,(_=t.__k[o]=(_=e[o])==null||typeof _=="boolean"||typeof _=="function"?null:typeof _=="string"||typeof _=="number"||typeof _=="bigint"||_.constructor==String?W(null,_,null,null,null):_e(_)?W(M,{children:_},null,null,null):_.constructor===void 0&&_.__b>0?W(_.type,_.props,_.key,_.ref?_.ref:null,_.__v):_)!=null?(_.__=t,_.__b=t.__b+1,u=Ve(_,n,a,y),_.__i=u,i=null,u!==-1&&(y--,(i=n[u])&&(i.__u|=131072)),i==null||i.__v===null?(u==-1&&l--,typeof _.type!="function"&&(_.__u|=65536)):u!==a&&(u===a+1?l++:u>a?y>s-a?l+=u-a:l--:u<a?u==a-1&&(l=u-a):l=0,u!==o+l&&(_.__u|=65536))):(i=n[a])&&i.key==null&&i.__e&&!(131072&i.__u)&&(i.__e==t.__d&&(t.__d=N(i)),ue(i,i,!1),n[a]=null,y--);if(y)for(o=0;o<c;o++)(i=n[o])!=null&&!(131072&i.__u)&&(i.__e==t.__d&&(t.__d=N(i)),ue(i,i))}function be(t,e,n){var o,_;if(typeof t.type=="function"){for(o=t.__k,_=0;o&&_<o.length;_++)o[_]&&(o[_].__=t,e=be(o[_],e,n));return e}t.__e!=e&&(n.insertBefore(t.__e,e||null),e=t.__e);do e=e&&e.nextSibling;while(e!=null&&e.nodeType===8);return e}function Ve(t,e,n,o){var _=t.key,i=t.type,a=n-1,u=n+1,s=e[n];if(s===null||s&&_==s.key&&i===s.type&&!(131072&s.__u))return n;if(o>(s!=null&&!(131072&s.__u)?1:0))for(;a>=0||u<e.length;){if(a>=0){if((s=e[a])&&!(131072&s.__u)&&_==s.key&&i===s.type)return a;a--}if(u<e.length){if((s=e[u])&&!(131072&s.__u)&&_==s.key&&i===s.type)return u;u++}}return-1}function Te(t,e,n){e[0]==="-"?t.setProperty(e,n??""):t[e]=n==null?"":typeof n!="number"||Xe.test(e)?n:n+"px"}function G(t,e,n,o,_){var i;e:if(e==="style")if(typeof n=="string")t.style.cssText=n;else{if(typeof o=="string"&&(t.style.cssText=o=""),o)for(e in o)n&&e in n||Te(t.style,e,"");if(n)for(e in n)o&&n[e]===o[e]||Te(t.style,e,n[e])}else if(e[0]==="o"&&e[1]==="n")i=e!==(e=e.replace(/(PointerCapture)$|Capture$/i,"$1")),e=e.toLowerCase()in t||e==="onFocusOut"||e==="onFocusIn"?e.toLowerCase().slice(2):e.slice(2),t.l||(t.l={}),t.l[e+i]=n,n?o?n.u=o.u:(n.u=ne,t.addEventListener(e,i?oe:re,i)):t.removeEventListener(e,i?oe:re,i);else{if(_)e=e.replace(/xlink(H|:h)/,"h").replace(/sName$/,"s");else if(e!="width"&&e!="height"&&e!="href"&&e!="list"&&e!="form"&&e!="tabIndex"&&e!="download"&&e!="rowSpan"&&e!="colSpan"&&e!="role"&&e in t)try{t[e]=n??"";break e}catch{}typeof n=="function"||(n==null||n===!1&&e[4]!=="-"?t.removeAttribute(e):t.setAttribute(e,n))}}function Ae(t){return function(e){if(this.l){var n=this.l[e.type+t];if(e.t==null)e.t=ne++;else if(e.t<n.u)return;return n(b.event?b.event(e):e)}}}function ie(t,e,n,o,_,i,a,u,s,c){var y,l,g,r,f,d,p,h,m,v,T,E,R,U,I,w=e.type;if(e.constructor!==void 0)return null;128&n.__u&&(s=!!(32&n.__u),i=[u=e.__e=n.__e]),(y=b.__b)&&y(e);e:if(typeof w=="function")try{if(h=e.props,m=(y=w.contextType)&&o[y.__c],v=y?m?m.props.value:y.__:o,n.__c?p=(l=e.__c=n.__c).__=l.__E:("prototype"in w&&w.prototype.render?e.__c=l=new w(h,v):(e.__c=l=new X(h,v),l.constructor=w,l.render=Ye),m&&m.sub(l),l.props=h,l.state||(l.state={}),l.context=v,l.__n=o,g=l.__d=!0,l.__h=[],l._sb=[]),l.__s==null&&(l.__s=l.state),w.getDerivedStateFromProps!=null&&(l.__s==l.state&&(l.__s=F({},l.__s)),F(l.__s,w.getDerivedStateFromProps(h,l.__s))),r=l.props,f=l.state,l.__v=e,g)w.getDerivedStateFromProps==null&&l.componentWillMount!=null&&l.componentWillMount(),l.componentDidMount!=null&&l.__h.push(l.componentDidMount);else{if(w.getDerivedStateFromProps==null&&h!==r&&l.componentWillReceiveProps!=null&&l.componentWillReceiveProps(h,v),!l.__e&&(l.shouldComponentUpdate!=null&&l.shouldComponentUpdate(h,l.__s,v)===!1||e.__v===n.__v)){for(e.__v!==n.__v&&(l.props=h,l.state=l.__s,l.__d=!1),e.__e=n.__e,e.__k=n.__k,e.__k.forEach(function(ee){ee&&(ee.__=e)}),T=0;T<l._sb.length;T++)l.__h.push(l._sb[T]);l._sb=[],l.__h.length&&a.push(l);break e}l.componentWillUpdate!=null&&l.componentWillUpdate(h,l.__s,v),l.componentDidUpdate!=null&&l.__h.push(function(){l.componentDidUpdate(r,f,d)})}if(l.context=v,l.props=h,l.__P=t,l.__e=!1,E=b.__r,R=0,"prototype"in w&&w.prototype.render){for(l.state=l.__s,l.__d=!1,E&&E(e),y=l.render(l.props,l.state,l.context),U=0;U<l._sb.length;U++)l.__h.push(l._sb[U]);l._sb=[]}else do l.__d=!1,E&&E(e),y=l.render(l.props,l.state,l.context),l.state=l.__s;while(l.__d&&++R<25);l.state=l.__s,l.getChildContext!=null&&(o=F(F({},o),l.getChildContext())),g||l.getSnapshotBeforeUpdate==null||(d=l.getSnapshotBeforeUpdate(r,f)),Ee(t,_e(I=y!=null&&y.type===M&&y.key==null?y.props.children:y)?I:[I],e,n,o,_,i,a,u,s,c),l.base=e.__e,e.__u&=-161,l.__h.length&&a.push(l),p&&(l.__E=l.__=null)}catch(ee){e.__v=null,s||i!=null?(e.__e=u,e.__u|=s?160:32,i[i.indexOf(u)]=null):(e.__e=n.__e,e.__k=n.__k),b.__e(ee,e,n)}else i==null&&e.__v===n.__v?(e.__k=n.__k,e.__e=n.__e):e.__e=je(n.__e,e,n,o,_,i,a,s,c);(y=b.diffed)&&y(e)}function xe(t,e,n){e.__d=void 0;for(var o=0;o<n.length;o++)le(n[o],n[++o],n[++o]);b.__c&&b.__c(e,t),t.some(function(_){try{t=_.__h,_.__h=[],t.some(function(i){i.call(_)})}catch(i){b.__e(i,_.__v)}})}function je(t,e,n,o,_,i,a,u,s){var c,y,l,g,r,f,d,p=n.props,h=e.props,m=e.type;if(m==="svg"&&(_=!0),i!=null){for(c=0;c<i.length;c++)if((r=i[c])&&"setAttribute"in r==!!m&&(m?r.localName===m:r.nodeType===3)){t=r,i[c]=null;break}}if(t==null){if(m===null)return document.createTextNode(h);t=_?document.createElementNS("http://www.w3.org/2000/svg",m):document.createElement(m,h.is&&h),i=null,u=!1}if(m===null)p===h||u&&t.data===h||(t.data=h);else{if(i=i&&$.call(t.childNodes),p=n.props||C,!u&&i!=null)for(p={},c=0;c<t.attributes.length;c++)p[(r=t.attributes[c]).name]=r.value;for(c in p)r=p[c],c=="children"||(c=="dangerouslySetInnerHTML"?l=r:c==="key"||c in h||G(t,c,null,r,_));for(c in h)r=h[c],c=="children"?g=r:c=="dangerouslySetInnerHTML"?y=r:c=="value"?f=r:c=="checked"?d=r:c==="key"||u&&typeof r!="function"||p[c]===r||G(t,c,r,p[c],_);if(y)u||l&&(y.__html===l.__html||y.__html===t.innerHTML)||(t.innerHTML=y.__html),e.__k=[];else if(l&&(t.innerHTML=""),Ee(t,_e(g)?g:[g],e,n,o,_&&m!=="foreignObject",i,a,i?i[0]:n.__k&&N(n,0),u,s),i!=null)for(c=i.length;c--;)i[c]!=null&&ye(i[c]);u||(c="value",f!==void 0&&(f!==t[c]||m==="progress"&&!f||m==="option"&&f!==p[c])&&G(t,c,f,p[c],!1),c="checked",d!==void 0&&d!==t[c]&&G(t,c,d,p[c],!1))}return t}function le(t,e,n){try{typeof t=="function"?t(e):t.current=e}catch(o){b.__e(o,n)}}function ue(t,e,n){var o,_;if(b.unmount&&b.unmount(t),(o=t.ref)&&(o.current&&o.current!==t.__e||le(o,null,e)),(o=t.__c)!=null){if(o.componentWillUnmount)try{o.componentWillUnmount()}catch(i){b.__e(i,e)}o.base=o.__P=null}if(o=t.__k)for(_=0;_<o.length;_++)o[_]&&ue(o[_],e,n||typeof t.type!="function");n||t.__e==null||ye(t.__e),t.__c=t.__=t.__e=t.__d=void 0}function Ye(t,e,n){return this.constructor(t,n)}function ze(t,e,n){var o,_,i,a;b.__&&b.__(t,e),_=(o=typeof n=="function")?null:n&&n.__k||e.__k,i=[],a=[],ie(e,t=(!o&&n||e).__k=Oe(M,null,[t]),_||C,C,e.ownerSVGElement!==void 0,!o&&n?[n]:_?null:e.firstChild?$.call(e.childNodes):null,i,!o&&n?n:_?_.__e:e.firstChild,o,a),xe(i,t,a)}$=me.slice,b={__e:function(t,e,n,o){for(var _,i,a;e=e.__;)if((_=e.__c)&&!_.__)try{if((i=_.constructor)&&i.getDerivedStateFromError!=null&&(_.setState(i.getDerivedStateFromError(t)),a=_.__d),_.componentDidCatch!=null&&(_.componentDidCatch(t,o||{}),a=_.__d),a)return _.__E=_}catch(u){t=u}throw t}},pe=0,X.prototype.setState=function(t,e){var n;n=this.__s!=null&&this.__s!==this.state?this.__s:this.__s=F({},this.state),typeof t=="function"&&(t=t(F({},n),this.props)),t&&F(n,t),t!=null&&this.__v&&(e&&this._sb.push(e),ve(this))},X.prototype.forceUpdate=function(t){this.__v&&(this.__e=!0,t&&this.__h.push(t),ve(this))},X.prototype.render=M,P=[],he=typeof Promise=="function"?Promise.prototype.then.bind(Promise.resolve()):setTimeout,te=function(t,e){return t.__v.__b-e.__v.__b},O.__r=0,ne=0,re=Ae(!1),oe=Ae(!0);var L,A,ae,we,V=0,Re=[],j=[],x=b,Ue=x.__b,ke=x.__r,Se=x.diffed,Fe=x.__c,De=x.unmount,Ie=x.__;function ce(t,e){x.__h&&x.__h(A,t,V||e),V=0;var n=A.__H||(A.__H={__:[],__h:[]});return t>=n.__.length&&n.__.push({__V:j}),n.__[t]}function Y(t){return V=1,qe(Ce,t)}function qe(t,e,n){var o=ce(L++,2);if(o.t=t,!o.__c&&(o.__=[n?n(e):Ce(void 0,e),function(u){var s=o.__N?o.__N[0]:o.__[0],c=o.t(s,u);s!==c&&(o.__N=[c,o.__[1]],o.__c.setState({}))}],o.__c=A,!A.u)){var _=function(u,s,c){if(!o.__c.__H)return!0;var y=o.__c.__H.__.filter(function(g){return!!g.__c});if(y.every(function(g){return!g.__N}))return!i||i.call(this,u,s,c);var l=!1;return y.forEach(function(g){if(g.__N){var r=g.__[0];g.__=g.__N,g.__N=void 0,r!==g.__[0]&&(l=!0)}}),!(!l&&o.__c.props===u)&&(!i||i.call(this,u,s,c))};A.u=!0;var i=A.shouldComponentUpdate,a=A.componentWillUpdate;A.componentWillUpdate=function(u,s,c){if(this.__e){var y=i;i=void 0,_(u,s,c),i=y}a&&a.call(this,u,s,c)},A.shouldComponentUpdate=_}return o.__N||o.__}function Pe(t,e){var n=ce(L++,3);!x.__s&&Be(n.__H,e)&&(n.__=t,n.i=e,A.__H.__h.push(n))}function Je(t){return V=5,Ke(function(){return{current:t}},[])}function Ke(t,e){var n=ce(L++,7);return Be(n.__H,e)?(n.__V=t(),n.i=e,n.__h=t,n.__V):n.__}function Ze(){for(var t;t=Re.shift();)if(t.__P&&t.__H)try{t.__H.__h.forEach(z),t.__H.__h.forEach(se),t.__H.__h=[]}catch(e){t.__H.__h=[],x.__e(e,t.__v)}}x.__b=function(t){A=null,Ue&&Ue(t)},x.__=function(t,e){t&&e.__k&&e.__k.__m&&(t.__m=e.__k.__m),Ie&&Ie(t,e)},x.__r=function(t){ke&&ke(t),L=0;var e=(A=t.__c).__H;e&&(ae===A?(e.__h=[],A.__h=[],e.__.forEach(function(n){n.__N&&(n.__=n.__N),n.__V=j,n.__N=n.i=void 0})):(e.__h.forEach(z),e.__h.forEach(se),e.__h=[],L=0)),ae=A},x.diffed=function(t){Se&&Se(t);var e=t.__c;e&&e.__H&&(e.__H.__h.length&&(Re.push(e)!==1&&we===x.requestAnimationFrame||((we=x.requestAnimationFrame)||Qe)(Ze)),e.__H.__.forEach(function(n){n.i&&(n.__H=n.i),n.__V!==j&&(n.__=n.__V),n.i=void 0,n.__V=j})),ae=A=null},x.__c=function(t,e){e.some(function(n){try{n.__h.forEach(z),n.__h=n.__h.filter(function(o){return!o.__||se(o)})}catch(o){e.some(function(_){_.__h&&(_.__h=[])}),e=[],x.__e(o,n.__v)}}),Fe&&Fe(t,e)},x.unmount=function(t){De&&De(t);var e,n=t.__c;n&&n.__H&&(n.__H.__.forEach(function(o){try{z(o)}catch(_){e=_}}),n.__H=void 0,e&&x.__e(e,n.__v))};var Ne=typeof requestAnimationFrame=="function";function Qe(t){var e,n=function(){clearTimeout(o),Ne&&cancelAnimationFrame(e),setTimeout(t)},o=setTimeout(n,100);Ne&&(e=requestAnimationFrame(n))}function z(t){var e=A,n=t.__c;typeof n=="function"&&(t.__c=void 0,n()),A=e}function se(t){var e=A;t.__c=t.__(),A=e}function Be(t,e){return!t||t.length!==e.length||e.some(function(n,o){return n!==t[o]})}function Ce(t,e){return typeof e=="function"?e(t):e}const et=async(t={},e)=>{let n;if(e.startsWith("data:")){const o=e.replace(/^data:.*?base64,/,"");let _;if(typeof Buffer=="function"&&typeof Buffer.from=="function")_=Buffer.from(o,"base64");else if(typeof atob=="function"){const i=atob(o);_=new Uint8Array(i.length);for(let a=0;a<i.length;a++)_[a]=i.charCodeAt(a)}else throw new Error("Failed to decode base64-encoded data URL, Buffer and atob are not supported");n=await WebAssembly.instantiate(_,t)}else{const o=await fetch(e),_=o.headers.get("Content-Type")||"";if("instantiateStreaming"in WebAssembly&&_.startsWith("application/wasm"))n=await WebAssembly.instantiateStreaming(o,t);else{const i=await o.arrayBuffer();n=await WebAssembly.instantiate(i,t)}}return n.instance},tt=t=>et(t,""+new URL("game-C4A2i_kk.wasm?init",import.meta.url).href);let q=null,fe=null;function nt(t,e){const n=new TextDecoder().decode(new Uint8Array(B.exports.memory.buffer,t,e));q==null?console.log(n):q(n)}function rt(t,e){const n=new TextDecoder().decode(new Uint8Array(B.exports.memory.buffer,t,e));console.log(n)}function ot(t,e){const n=new TextDecoder().decode(new Uint8Array(B.exports.memory.buffer,t,e));fe==null?console.error(n):fe(n)}const B=await tt({env:{memory:new WebAssembly.Memory({initial:2}),messageFromWasm:nt,errorFromWasm:ot,debugLogFromWasm:rt}});function Me(t,...e){const n=Le(t),o=Le(JSON.stringify(e));let _=null;q=i=>{_=JSON.parse(i)},fe=i=>{_={error:i}};try{B.exports.callWithJson(n.ptr,n.len,o.ptr,o.len)}catch(i){_={error:i.message}}return q=null,_}function Le(t){const e=new TextEncoder().encode(t),n=B.exports.allocUint8(e.length+1),o=new Uint8Array(B.exports.memory.buffer,n,e.length+1);return o.set(e),o[e.length]=0,{type:"Uint8Array",ptr:n,len:e.length}}function D(t,e){return n=>new e(B.exports.memory.buffer,n.ptr,n.len)}const J={Uint8ClampedArray:D("Uint8Array",Uint8ClampedArray),Uint8Array:D("Uint8Array",Uint8Array),Uint16Array:D("Uint16Array",Uint16Array),Uint32Array:D("Uint32Array",Uint32Array),Int8Array:D("Int8Array",Int8Array),Int16Array:D("Int16Array",Int16Array),Int32Array:D("Int32Array",Int32Array),Float32Array:D("Float32Array",Float32Array)},_t="updateNodeGraph";function it(t){const e=n(t);function n(o){const _=Me(_t,o);return"error"in _?_:_.outputs}return{call:n,useState:()=>{const[o,_]=Y(e);return{graphOutputs:o,callGraph:i=>{const a=n(i);a!=null&&_(a)}}}}}function lt(t){const e=Object.keys(t).reduce((_,i)=>{const a=i.split(".");return[..._,...a]},[]),n=e.reduce((_,i)=>(_[i]=i,_),{}),o=e.reduce((_,i)=>{const a=t[i],u=Object.keys(a).filter(s=>s.startsWith("&")).map(s=>{const c=`${i}${s.split("&")[1]}`;return a[c]=void 0,[c,a[s]]});return[..._,[i,a],...u]},[]).map(_=>{const[i,a]=_;return`.${i} {${Object.keys(a).map(u=>`${u.replace(/[A-Z]/g,s=>`-${s.toLowerCase()}`)}: ${a[u]};`).join("")}}`}).join("");return{classes:n,encodedStyle:o}}function He(t){return Object.keys(t)}const $e={float:1,vec2:2,vec3:3,vec4:4,mat4:16};var S;(t=>{function e(r,f){return`${f.type} highp ${f.unit} ${r};`}t.varyingText=e;function n(r,f){return`${f.type} ${f.unit} ${r}; `}t.attributeText=n;function o(r,f){return`${f.type} ${f.unit=="sampler2D"?"":"highp"} ${f.unit} ${r}${f.count>1?`[${f.count}]`:""};`}t.uniformText=o;function _(r){return He(r).reduce((f,d)=>{const p=r[d];return`${f}
 ${p.type=="varying"?e(d,p):p.type=="attribute"?n(d,p):p.type=="uniform"?o(d,p):""}`},"")}t.toVertText=_;function i(r){return He(r).reduce((f,d)=>{const p=r[d];return`${f}${p.type=="varying"?e(d,p):p.type=="uniform"?o(d,p):""}
`},"")}t.toFragText=i;function a(r,f){const d=r.createProgram();if(d==null)throw new Error("Vertex/Fragment shader not properly initialized");const p=`
			${_(f.globals)}
			${f.vertSource}
		`,h=`
			${i(f.globals)}
			${f.fragSource}
		`;return[p,h].forEach((m,v)=>{var E;const T=r.createShader(v==0?r.VERTEX_SHADER:r.FRAGMENT_SHADER);if(T==null)throw new Error("Vertex/Fragment shader not properly initialized");if(r.shaderSource(T,m),r.compileShader(T),r.attachShader(d,T),!r.getShaderParameter(T,r.COMPILE_STATUS)){console.log(m);const R=(E=r.getShaderInfoLog(T))==null?void 0:E.split("ERROR:");if(R!=null){const U=R.slice(1,R==null?void 0:R.length);for(let I of U){const w=I.split(":")[1];console.log(m.split(`
`)[parseInt(w)-1]),console.error(I)}}}}),r.linkProgram(d),{...f,program:d,fragSource:h,vertSource:p}}t.generateMaterial=a;function u(r,f,d,p){const h=r.createTexture();if(h==null)throw new Error("Texture is null, this is not expected!");return r.bindTexture(r.TEXTURE_2D,h),r.texImage2D(r.TEXTURE_2D,0,r.RGBA,d,p,0,r.RGBA,r.UNSIGNED_BYTE,f),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_WRAP_S,r.REPEAT),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_WRAP_T,r.REPEAT),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_MIN_FILTER,r.LINEAR),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_MAG_FILTER,r.LINEAR),r.generateMipmap(r.TEXTURE_2D),{texture:h,width:d,height:p}}t.loadImageData=u;async function s(r,f){return await new Promise(d=>{const p=r.createTexture();if(p==null)throw new Error("Texture is null, this is not expected!");r.bindTexture(r.TEXTURE_2D,p);const h={level:0,internalFormat:r.RGBA,srcFormat:r.RGBA,srcType:r.UNSIGNED_BYTE},m=new Image;m.onload=()=>{r.bindTexture(r.TEXTURE_2D,p),r.texImage2D(r.TEXTURE_2D,h.level,h.internalFormat,h.srcFormat,h.srcType,m),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_WRAP_S,r.REPEAT),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_WRAP_T,r.REPEAT),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_MIN_FILTER,r.LINEAR),r.texParameteri(r.TEXTURE_2D,r.TEXTURE_MAG_FILTER,r.LINEAR),r.generateMipmap(r.TEXTURE_2D),d({texture:p,width:m.width,height:m.height})},m.src=f})}t.loadTexture=s;function c(r,f){const d=r.createBuffer();if(d==null)throw new Error("Buffer is null, this is not expected!");return r.bindBuffer(r.ELEMENT_ARRAY_BUFFER,d),r.bufferData(r.ELEMENT_ARRAY_BUFFER,f,r.STATIC_DRAW),{type:"element",buffer:d,length:f.length,glType:f.BYTES_PER_ELEMENT==2?"UNSIGNED_SHORT":"UNSIGNED_INT"}}t.createElementBuffer=c;function y(r,f){const d=r.createBuffer();if(d==null)throw new Error("Buffer is null, this is not expected!");return r.bindBuffer(r.ARRAY_BUFFER,d),r.bufferData(r.ARRAY_BUFFER,f,r.STATIC_DRAW),{type:"attribute",buffer:d,length:f.length}}t.createBuffer=y;function l(r,f,d){r.useProgram(f.program),Object.entries(f.globals).filter(p=>p[1].type=="uniform").reduce((p,h)=>{const[m,v]=h,T=r.getUniformLocation(f.program,m),E=d[m];switch(v.unit){case"sampler2D":const R=(v.count>1?E:[E]).map((U,I)=>{const w=p+I;return r.activeTexture(r.TEXTURE0+w),r.bindTexture(r.TEXTURE_2D,U.texture),w});return r.uniform1iv(T,R),p+R.length;case"float":r.uniform1fv(T,v.count>1?E:[E]);break;case"vec2":r.uniform2fv(T,v.count>1?E.flat():[...E]);break;case"vec3":r.uniform3fv(T,v.count>1?E.flat():[...E]);break;case"vec4":r.uniform4fv(T,v.count>1?E.flat():[...E]);break;case"mat4":r.uniformMatrix4fv(T,!1,v.count>1?E.flat():[...E]);break}return p},0),Object.entries(f.globals).filter(p=>p[1].type=="attribute").forEach(p=>{const[h,m]=p,v=d[h];r.bindBuffer(r.ARRAY_BUFFER,v.buffer);const T=r.getAttribLocation(f.program,h);if(T==-1){console.error(`Attribute ${h} not found in shader`);return}const E=m.unit;r.vertexAttribPointer(T,$e[E],r.FLOAT,!1,0,0),r.enableVertexAttribArray(T),m.instanced&&r.vertexAttribDivisor(T,1)});{const p=Object.entries(f.globals).filter(m=>m[1].type=="attribute").reduce((m,v)=>{const[T,E]=v,R=d[T],U=$e[E.unit];return E.instanced?{...m,instance:Math.max(m.instance,R.length/U)}:{...m,element:Math.max(m.element,R.length/U)}},{element:0,instance:1}),h=Object.entries(f.globals).find(m=>m[1].type=="element");if(h!=null){const[m]=h,v=d[m];r.bindBuffer(r.ELEMENT_ARRAY_BUFFER,v.buffer),r.drawElementsInstanced(r[f.mode],v.length,r[v.glType],0,p.instance)}else r.drawArraysInstanced(r[f.mode],0,p.element,p.instance)}}t.renderMaterial=l;function g(r,f){Object.values(f).forEach(d=>{"type"in d&&(d.type=="attribute"||d.type=="element")?r.deleteBuffer(d.buffer):r.deleteTexture(d.texture)})}t.cleanupResources=g})(S||(S={}));var ut=0;function k(t,e,n,o,_,i){var a,u,s={};for(u in e)u=="ref"?a=e[u]:s[u]=e[u];var c={type:t,props:s,key:n,ref:a,__k:null,__:null,__b:0,__e:null,__d:void 0,__c:null,constructor:void 0,__v:--ut,__i:-1,__u:0,__source:_,__self:i};if(typeof t=="function"&&(a=t.defaultProps))for(u in a)s[u]===void 0&&(s[u]=a[u]);return b.vnode&&b.vnode(c),c}const{classes:We,encodedStyle:at}=lt({stats:{position:"absolute",top:"0px",left:"0px",color:"#fff",backgroundColor:"#000",padding:"5px",borderRadius:"5px"},nodeGraph:{},nodeGraphBackground:{backgroundColor:"#555",position:"absolute",top:"0px",left:"0px",width:"100%",height:"100vh",zIndex:"-1"},node:{},contextMenu:{display:"flex",position:"absolute",flexDirection:"column",width:"max-content",backgroundColor:"#333",borderRadius:"10px"},contextMenuSeperator:{height:"1px",margin:"5px",backgroundColor:"#0008"},contextMenuItem:{backgroundColor:"#0000"},canvas:{width:"100%",height:"100%",position:"absolute",left:0,top:0,zIndex:-1}});let K={game_time_ms:0,user_changes:{resolution_update:{x:window.innerWidth,y:window.innerHeight}}},Z=null;function H(t){K=t;const e=ct.call(K);e==null||"error"in e||(Z==null||Z(e)())}Me("init");const ct=it(K);let Q=null;function st(){const t=Je(null),[e,n]=Y({width:window.innerWidth,height:window.innerHeight}),[o,_]=Y(0),[i,a]=Y({polygonCount:0,framerate:0});return Pe(()=>{const u=()=>{var s,c;n({width:((s=t.current)==null?void 0:s.width)||0,height:((c=t.current)==null?void 0:c.height)||0}),H({game_time_ms:Date.now(),user_changes:{resolution_update:{x:window.innerWidth,y:window.innerHeight}}})};return window.addEventListener("resize",u),()=>{window.removeEventListener("resize",u)}},[]),Pe(()=>{if(!t.current)return;const u=t.current.getContext("webgl2");if(!u)return;u.enable(u.BLEND),u.blendFunc(u.ONE,u.ONE_MINUS_SRC_ALPHA),u.enable(u.DEPTH_TEST);const s=S.generateMaterial(u,{mode:"TRIANGLES",globals:{indices:{type:"element"},position:{type:"attribute",unit:"vec3"},normals:{type:"attribute",unit:"vec3"},colors:{type:"attribute",unit:"vec3"},color:{type:"varying",unit:"vec3"},normal:{type:"varying",unit:"vec3"},item_position:{type:"attribute",unit:"vec3",instanced:!0},perspectiveMatrix:{type:"uniform",unit:"mat4",count:1}},vertSource:`
        precision highp float;
        void main(void) {
          gl_Position = perspectiveMatrix * vec4(item_position + position, 1);
          normal = normals;
          color = colors;
        }
      `,fragSource:`
        precision highp float;
        void main(void) {
          // gl_FragColor = vec4(color, 1);
          gl_FragColor = vec4(normal * 0.5 + 0.5, 1);
        }
      `});Z=l=>()=>{const g={indices:S.createElementBuffer(u,J.Uint32Array(l.current_cat_mesh.indices)),position:S.createBuffer(u,J.Float32Array(l.current_cat_mesh.position)),normals:S.createBuffer(u,J.Float32Array(l.current_cat_mesh.normal)),colors:S.createBuffer(u,J.Float32Array(l.current_cat_mesh.color)),item_position:S.createBuffer(u,new Float32Array([0,0,0])),perspectiveMatrix:l.world_matrix.flatMap(r=>r)};requestAnimationFrame(()=>{u.viewport(0,0,e.width,e.height),u.clearColor(0,0,0,1),u.clear(u.COLOR_BUFFER_BIT|u.DEPTH_BUFFER_BIT),S.renderMaterial(u,s,g),a({polygonCount:g.indices.length/3,framerate:1e3/(Date.now()-K.game_time_ms)})})},H({game_time_ms:Date.now()});let c=!0;const y=setInterval(()=>{c||clearInterval(y),document.hasFocus()&&H({game_time_ms:Date.now()})},1e3/24);return()=>c=!1},[]),k(M,{children:[k("style",{children:at}),k("div",{style:{width:"100%",height:"100%",zIndex:1,position:"absolute",left:0,top:0},onMouseMove:u=>{const s={x:u.clientX,y:u.clientY},c=Q==null?s:{x:s.x-Q.x,y:s.y-Q.y};Q=s,u.buttons&&H({game_time_ms:Date.now(),input:{mouse_delta:[c.x,c.y,0,0]}})},children:["// Select a subdivision detail between 0-3",k("input",{type:"range",min:"0",max:"4",value:o,onChange:u=>{_(parseInt(u.target.value)),H({game_time_ms:Date.now(),user_changes:{subdiv_level_update:parseInt(u.target.value)}})}}),k("div",{class:We.stats,children:[k("div",{children:["subdiv_level - ",o]}),k("div",{children:["polygon_count - ",i.polygonCount]}),k("div",{children:["frame_rate - ",""+Math.round(i.framerate)]})]})]}),k("canvas",{ref:t,class:We.canvas,id:"canvas",width:e.width,height:e.height})]})}ze(k(st,{}),document.getElementById("app"))})();