/* Pré-compila app.jsx (código do app) em app.compiled.js e grava a chave no index.html.
   Rode SEMPRE depois de editar app.jsx:  node scripts/build_app.js [babel.min.js]
   (mesma versão do Babel do navegador: 7.23.2). O carregador do index.html só usa o
   compilado se a chave bater; senão baixa app.jsx e compila no aparelho (lento). */
const fs=require('fs'), path=require('path');
const raiz=path.join(__dirname,'..');
const Babel=require(process.argv[2]||require.resolve('@babel/standalone'));
const src=fs.readFileSync(path.join(raiz,'app.jsx'),'utf8');
const norm=src.replace(/\r\n?/g,'\n');
function fnv(s){ let h=2166136261>>>0; for(let i=0;i<s.length;i++){ h^=s.charCodeAt(i); h=Math.imul(h,16777619)>>>0; } return h.toString(36); }
const key=norm.length.toString(36)+'.'+fnv(norm);
const ip=path.join(raiz,'index.html'); let html=fs.readFileSync(ip,'utf8');
const re=/(<script type="text\/x-preceptor-app" id="preceptor-app" data-key=")[^"]*("><\/script>)/;
if(!re.test(html)) throw new Error('marcador do app não encontrado no index.html');
html=html.replace(re,'$1'+key+'$2'); fs.writeFileSync(ip,html);
const ver=(/window\.APP_VERSION="([^"]*)"/.exec(html)||[])[1]||'';
const chave='app|'+ver+'|'+key;
const t0=Date.now();
const code=Babel.transform(norm,{filename:'preceptor.jsx',presets:['react','env'],
  plugins:['transform-class-properties','transform-object-rest-spread','transform-flow-strip-types'],compact:true}).code;
fs.writeFileSync(path.join(raiz,'app.compiled.js'),'//KEY:'+chave+'\n'+code);
console.log('ok',chave,(code.length/1e6).toFixed(2)+' MB',(Date.now()-t0)+' ms');
