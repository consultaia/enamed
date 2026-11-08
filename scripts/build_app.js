/* Pré-compila o app (bloco <script id="preceptor-app"> do index.html) para app.compiled.js.
   O carregador do index.html usa este arquivo quando a chave bate com o código atual;
   se não bater (arquivo velho), cai no Babel do navegador, como antes.
   Uso: node scripts/build_app.js [caminho/para/@babel/standalone/babel.min.js]
   (mesma versão do Babel do navegador: 7.23.2) */
const fs=require('fs'), path=require('path');
const raiz=path.join(__dirname,'..');
const babelPath=process.argv[2]||require.resolve('@babel/standalone');
const Babel=require(babelPath);
const html=fs.readFileSync(path.join(raiz,'index.html'),'utf8');
const ini=html.indexOf('id="preceptor-app"'); if(ini<0) throw new Error('bloco do app não encontrado');
const a=html.indexOf('>',ini)+1, b=html.indexOf('</script>',a);
/* o parser HTML do navegador converte CRLF e CR em LF: textContent vem assim */
const src=html.slice(a,b).replace(/\r\n?/g,'\n');
const ver=(/window\.APP_VERSION="([^"]*)"/.exec(html)||[])[1]||'';
function fnv(s){ let h=2166136261>>>0; for(let i=0;i<s.length;i++){ h^=s.charCodeAt(i); h=Math.imul(h,16777619)>>>0; } return h.toString(36); }
const chave='app|'+ver+'|'+src.length+'|'+fnv(src);
const t0=Date.now();
const code=Babel.transform(src,{filename:'preceptor.jsx',presets:['react','env'],
  plugins:['transform-class-properties','transform-object-rest-spread','transform-flow-strip-types'],compact:true}).code;
fs.writeFileSync(path.join(raiz,'app.compiled.js'),'//KEY:'+chave+'\n'+code);
console.log('ok',chave,(code.length/1e6).toFixed(2)+' MB',(Date.now()-t0)+' ms');
