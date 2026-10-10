// Teste de contrato dos eventos operacional.*.v1 (OPR-INFRA-2): compila os JSON Schemas de
// contracts/operacional e confere que todo exemplo valido passa e todo invalido falha.
// Uso: npm ci && npm test   (sai 1 se algum caso divergir)
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const pasta = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'contracts', 'operacional');
const lerJson = (arquivo) => JSON.parse(readFileSync(arquivo, 'utf8'));
const jsons = (dir) => readdirSync(dir).filter((n) => n.endsWith('.json')).sort();

const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true });
addFormats(ajv);
for (const nome of jsons(pasta)) ajv.addSchema(lerJson(join(pasta, nome)));

const validador = (contrato) => {
  const id = `https://contracts.b3-ecossistema.local/operacional/${contrato}.v1.schema.json`;
  const validar = ajv.getSchema(id);
  if (!validar) throw new Error(`schema inexistente: ${id}`);
  return validar;
};

let falhas = 0;
let casos = 0;
const contratos = jsons(pasta).filter((n) => !/^(comum|status-sistema)\./.test(n)).map((n) => n.replace('.v1.schema.json', ''));
const cobertos = new Set();

for (const nome of jsons(join(pasta, 'exemplos', 'validos'))) {
  const { contrato, payload } = lerJson(join(pasta, 'exemplos', 'validos', nome));
  const validar = validador(contrato);
  casos += 1;
  cobertos.add(contrato);
  if (!validar(payload)) {
    falhas += 1;
    console.error(`FALHOU (valido rejeitado) ${nome}:`, JSON.stringify(validar.errors));
  } else {
    console.log(`  ok  valido   ${nome}`);
  }
}

for (const nome of jsons(join(pasta, 'exemplos', 'invalidos'))) {
  const { contrato, motivo, payload } = lerJson(join(pasta, 'exemplos', 'invalidos', nome));
  const validar = validador(contrato);
  casos += 1;
  if (validar(payload)) {
    falhas += 1;
    console.error(`FALHOU (invalido aceito) ${nome}: deveria recusar porque ${motivo}`);
  } else {
    console.log(`  ok  invalido ${nome} (${motivo})`);
  }
}

// Todo contrato precisa de ao menos um exemplo valido; o enum tem de bater com o CHECK da V23.
for (const contrato of contratos) {
  if (!cobertos.has(contrato)) {
    falhas += 1;
    console.error(`FALHOU: contrato ${contrato} sem exemplo valido`);
  }
}
const status = lerJson(join(pasta, 'status-sistema.v1.schema.json')).enum;
const v23 = readFileSync(resolve(pasta, '..', '..', 'mysql-migrations', 'V23__operacional_simulado.sql'), 'utf8');
const check = /ck_diario_status CHECK \(status_sistema IN\s*\(([^)]*)\)/.exec(v23);
const doBanco = check ? check[1].match(/'([A-Z_]+)'/g).map((s) => s.slice(1, -1)) : [];
casos += 1;
if (JSON.stringify(doBanco) !== JSON.stringify(status)) {
  falhas += 1;
  console.error(`FALHOU: enum de status ${JSON.stringify(status)} difere do CHECK da V23 ${JSON.stringify(doBanco)}`);
} else {
  console.log('  ok  enum de status igual ao CHECK ck_diario_status da V23');
}

console.log(`contratos operacionais: ${casos - falhas}/${casos} casos ok`);
if (falhas) process.exitCode = 1;
