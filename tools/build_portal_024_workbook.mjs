import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [inputPath, outputPath, previewDir] = process.argv.slice(2);
if (!inputPath || !outputPath || !previewDir) throw new Error("Uso: builder <json> <xlsx> <previews>");

const payload = JSON.parse(await fs.readFile(inputPath, "utf8"));
const wb = Workbook.create();
const summary = wb.worksheets.add("Resumo");
const list = wb.worksheets.add("Lista para importar");
const conflicts = wb.worksheets.add("Conflitos");
const excluded = wb.worksheets.add("Excluídos");

const navy = "#0D3454";
const blue = "#1287C5";
const orange = "#FF7A00";
const pale = "#EEF4F8";
const border = "#CAD5DF";
const headerFormat = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF" },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "all", style: "thin", color: border },
};
const asExcelText = (value) => value === null || value === undefined || value === "" ? "" : String(value);
const asTextFormula = (value) => value === null || value === undefined || value === "" ? '=""' : `="${String(value).replaceAll('"', '""')}"`;

function title(sheet, range, text, subtitle) {
  const endColumn = range.split(":")[1].replace(/\d+/g, "");
  const subtitleRange = `A2:${endColumn}2`;
  sheet.showGridLines = false;
  sheet.getRange(range).merge();
  sheet.getRange(range).values = [[text]];
  sheet.getRange(range).format = {
    fill: navy,
    font: { bold: true, color: "#FFFFFF", size: 18 },
    verticalAlignment: "center",
  };
  sheet.getRange(subtitleRange).merge();
  sheet.getRange(subtitleRange).values = [[subtitle]];
  sheet.getRange(subtitleRange).format = {
    fill: orange,
    font: { bold: true, color: "#FFFFFF", size: 10 },
    verticalAlignment: "center",
  };
  sheet.getRange(range).format.rowHeight = 34;
  sheet.getRange(subtitleRange).format.rowHeight = 24;
}

title(summary, "A1:J1", "RASTREADORES 024 — RELATÓRIO DE EXTRAÇÃO", "Somente leitura • RS300 e MANUTENÇÕES excluídos • revisão antes da importação");
const m = payload.metadata;
const summaryRows = [
  ["Indicador", "Quantidade / valor"],
  ["Páginas consultadas", m.pages_scanned],
  ["Linhas examinadas", m.rows_scanned],
  ["Rastreadores 024 encontrados", m.matched_024_before_exclusion],
  ["Selecionados para a lista", m.selected_rows],
  ["Excluídos — RS300", m.excluded_rs300],
  ["Excluídos — MANUTENÇÕES", m.excluded_manutencoes],
  ["Sem chip", m.missing_chip],
  ["Sem placa vinculada", m.missing_plate],
  ["Grupos com série duplicada", m.duplicate_serial_groups],
  ["Grupos com chip duplicado", m.duplicate_chip_groups],
  ["Fonte", m.source],
  ["Extraído em UTC", asExcelText(m.extracted_at_utc)],
];
summary.getRange("B16").setNumberFormat("@");
summary.getRange(`A4:B${3 + summaryRows.length}`).values = summaryRows;
summary.getRange("A4:B4").format = headerFormat;
summary.getRange(`A5:B${3 + summaryRows.length}`).format.borders = { preset: "all", style: "thin", color: border };
summary.getRange(`A5:A${3 + summaryRows.length}`).format.fill = pale;
summary.getRange(`A5:A${3 + summaryRows.length}`).format.font = { bold: true, color: navy };
summary.getRange("A4").format.columnWidth = 34;
summary.getRange("B4").format.columnWidth = 76;
summary.getRange("A17:J17").merge();
summary.getRange("A17:J17").values = [["Esta planilha não altera o portal nem o banco local. Revise os itens marcados como REVISAR antes de importar."]];
summary.getRange("A17:J17").format = { fill: "#FFF2CC", font: { bold: true, color: "#7A4E00" }, wrapText: true };
summary.freezePanes.freezeRows(2);

title(list, "A1:O1", "LISTA PARA IMPORTAR", "Todos serão importados como INSTALADO • data de instalação NÃO INFORMADA • pendências destacadas");
const listHeaders = ["Nº", "Número de série", "Número do chip", "Placa vinculada", "Cliente", "Modelo", "Telefone", "Status no banco", "Data de instalação", "Status no portal", "Situação", "Observação", "ID portal", "Página", "URL de origem"];
const listRows = payload.selected.map((x) => [
  x.indice_extracao, null, null, asExcelText(x.placa_vinculada), x.cliente, x.modelo,
  asExcelText(x.telefone), "Instalado", "Não informada", x.status, x.situacao_importacao, x.observacao, asExcelText(x.portal_id), x.pagina_origem, x.url_origem,
]);
list.getRange(`B5:D${4 + listRows.length}`).setNumberFormat("@");
list.getRange(`G5:G${4 + listRows.length}`).setNumberFormat("@");
list.getRange(`M5:M${4 + listRows.length}`).setNumberFormat("@");
list.getRange(`A4:O${4 + listRows.length}`).values = [listHeaders, ...listRows];
list.getRange(`B5:B${4 + listRows.length}`).formulas = payload.selected.map((x) => [asTextFormula(x.numero_serie)]);
list.getRange(`C5:C${4 + listRows.length}`).formulas = payload.selected.map((x) => [asTextFormula(x.numero_chip)]);
list.getRange("A4:O4").format = headerFormat;
list.getRange(`A5:O${4 + listRows.length}`).format.borders = { preset: "all", style: "thin", color: "#E1E7EC" };
list.getRange(`H5:I${4 + listRows.length}`).format = { fill: "#D9EAD3", font: { color: "#276221", bold: true } };
list.getRange(`K5:K${4 + listRows.length}`).conditionalFormats.addCustom('=K5="PRONTO"', { fill: "#D9EAD3", font: { color: "#276221", bold: true } });
list.getRange(`K5:K${4 + listRows.length}`).conditionalFormats.addCustom('=K5="REVISAR"', { fill: "#FCE8B2", font: { color: "#8A4B00", bold: true } });
list.tables.add(`A4:O${4 + listRows.length}`, true, "ListaImportacao024");
list.freezePanes.freezeRows(4);
const widths = [8, 18, 25, 18, 36, 18, 18, 16, 20, 16, 14, 30, 14, 10, 60];
for (let i = 0; i < widths.length; i++) list.getRangeByIndexes(3, i, 1, 1).format.columnWidth = widths[i];

title(conflicts, "A1:J1", "CONFLITOS E DUPLICIDADES", "Cada ocorrência é mantida; nenhuma informação foi descartada silenciosamente");
const conflictHeaders = ["Tipo", "Valor duplicado", "Número de série", "Chip", "Placa", "Cliente", "ID portal", "Página"];
const conflictRows = [];
for (const c of payload.conflicts) {
  for (const index of c.indices) {
    const x = payload.selected[index];
    conflictRows.push([c.tipo, null, null, null, asExcelText(x.placa_vinculada), x.cliente, asExcelText(x.portal_id), x.pagina_origem, c.valor, x.numero_serie, x.numero_chip]);
  }
}
conflicts.getRange(`B5:E${4 + conflictRows.length}`).setNumberFormat("@");
conflicts.getRange(`G5:G${4 + conflictRows.length}`).setNumberFormat("@");
conflicts.getRange(`A4:H${4 + conflictRows.length}`).values = [conflictHeaders, ...conflictRows.map((x) => x.slice(0, 8))];
if (conflictRows.length) {
  conflicts.getRange(`B5:B${4 + conflictRows.length}`).formulas = conflictRows.map((x) => [asTextFormula(x[8])]);
  conflicts.getRange(`C5:C${4 + conflictRows.length}`).formulas = conflictRows.map((x) => [asTextFormula(x[9])]);
  conflicts.getRange(`D5:D${4 + conflictRows.length}`).formulas = conflictRows.map((x) => [asTextFormula(x[10])]);
}
conflicts.getRange("A4:H4").format = headerFormat;
if (conflictRows.length) {
  conflicts.getRange(`A5:H${4 + conflictRows.length}`).format.borders = { preset: "all", style: "thin", color: border };
  conflicts.tables.add(`A4:H${4 + conflictRows.length}`, true, "Conflitos024");
}
conflicts.freezePanes.freezeRows(4);
for (let i = 0; i < 8; i++) conflicts.getRangeByIndexes(3, i, 1, 1).format.columnWidth = [26, 25, 20, 25, 18, 40, 14, 10][i];

title(excluded, "A1:J1", "REGISTROS EXCLUÍDOS PELO FILTRO", "Somente rastreadores 024 dos clientes RS300 ou MANUTENÇÕES");
const excludedHeaders = ["Motivo", "Número de série", "Chip", "Placa", "Cliente", "Modelo", "Status", "ID portal", "Página", "URL de origem"];
const excludedRows = payload.excluded.map((x) => [x.motivo_exclusao, null, null, asExcelText(x.placa_vinculada), x.cliente, x.modelo, x.status, asExcelText(x.portal_id), x.pagina_origem, x.url_origem]);
excluded.getRange(`B5:D${4 + excludedRows.length}`).setNumberFormat("@");
excluded.getRange(`H5:H${4 + excludedRows.length}`).setNumberFormat("@");
excluded.getRange(`A4:J${4 + excludedRows.length}`).values = [excludedHeaders, ...excludedRows];
excluded.getRange(`B5:B${4 + excludedRows.length}`).formulas = payload.excluded.map((x) => [asTextFormula(x.numero_serie)]);
excluded.getRange(`C5:C${4 + excludedRows.length}`).formulas = payload.excluded.map((x) => [asTextFormula(x.numero_chip)]);
excluded.getRange("A4:J4").format = headerFormat;
if (excludedRows.length) {
  excluded.getRange(`A5:J${4 + excludedRows.length}`).format.borders = { preset: "all", style: "thin", color: border };
  excluded.tables.add(`A4:J${4 + excludedRows.length}`, true, "Excluidos024");
}
excluded.freezePanes.freezeRows(4);
for (let i = 0; i < 10; i++) excluded.getRangeByIndexes(3, i, 1, 1).format.columnWidth = [20, 20, 25, 18, 40, 18, 12, 14, 10, 60][i];

await fs.mkdir(new URL(".", `file:///${outputPath.replaceAll("\\", "/")}`).pathname, { recursive: true }).catch(() => {});
await fs.mkdir(previewDir, { recursive: true });
const exported = await SpreadsheetFile.exportXlsx(wb);
await exported.save(outputPath);

const previewSpecs = [
  ["Resumo", "A1:J17", 1],
  ["Lista para importar", "A1:O24", 0.7],
  ["Conflitos", `A1:H${Math.min(4 + conflictRows.length, 40)}`, 0.9],
  ["Excluídos", `A1:J${Math.min(4 + excludedRows.length, 40)}`, 0.9],
];
for (const [sheetName, range, scale] of previewSpecs) {
  const preview = await wb.render({ sheetName, range, scale, format: "png" });
  const bytes = new Uint8Array(await preview.arrayBuffer());
  await fs.writeFile(`${previewDir}/${sheetName.replaceAll(" ", "_")}.png`, bytes);
}

const inspection = await wb.inspect({ kind: "sheet,table", maxChars: 6000, tableMaxRows: 5, tableMaxCols: 8 });
console.log(inspection.ndjson ?? inspection);
console.log(JSON.stringify({ outputPath, sheets: 4, rows: listRows.length, conflicts: conflictRows.length, excluded: excludedRows.length }));
