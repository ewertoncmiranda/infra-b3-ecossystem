// Fonte única: contracts/*.schema.json. Rode com --check no CI multi-repositório.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const infra = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workspace = resolve(infra, '..');
const check = process.argv.includes('--check');
const values = JSON.parse(readFileSync(resolve(infra, 'contracts/insight.schema.json'), 'utf8')).properties.resumo.properties.recomendacao.enum;
const files = new Map();
for (const name of ['ativos', 'series_historicas', 'insight']) {
  files.set(`gerar-insights/gerar-insights/contracts/${name}.schema.json`, readFileSync(resolve(infra, `contracts/${name}.schema.json`), 'utf8'));
}
files.set('gerar-insights/gerar-insights/app/contracts/recomendacao.py',
  '# Gerado por infra/scripts/sincronizar-contratos.mjs.\nfrom enum import StrEnum\n\n\nclass Recomendacao(StrEnum):\n' + values.map(v => `    ${v} = "${v}"\n`).join(''));
files.set('gestor-ativos-brutos/gestor-ativos-brutos/src/main/java/br/com/miranda/gestor/ativos/brutos/contracts/Recomendacao.java',
  '// Gerado por infra/scripts/sincronizar-contratos.mjs.\npackage br.com.miranda.gestor.ativos.brutos.contracts;\n\npublic enum Recomendacao {\n    ' + values.join(',\n    ') + ';\n}\n');
files.set('painel-ativos-frontend/public/js/contracts/recomendacao.js',
  '// Gerado por infra/scripts/sincronizar-contratos.mjs.\nexport const Recomendacao = Object.freeze(' + JSON.stringify(Object.fromEntries(values.map(v => [v, v])), null, 2) + ');\n');
let failed = false;
for (const [relative, content] of files) {
  const target = resolve(workspace, relative);
  if (check) {
    let actual;
    try { actual = readFileSync(target, 'utf8'); } catch { actual = ''; }
    if (actual.replaceAll('\r\n', '\n') !== content.replaceAll('\r\n', '\n')) {
      console.error(`Contrato divergente: ${relative}`);
      failed = true;
    }
  } else {
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, content);
  }
}
if (failed) process.exitCode = 1;
else console.log(check ? 'Contratos sincronizados.' : 'Contratos gerados.');
