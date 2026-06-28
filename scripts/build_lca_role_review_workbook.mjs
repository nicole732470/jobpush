#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [socCsvPath, rawCsvPath, outputPath, previewDir] = process.argv.slice(2);
if (!socCsvPath || !rawCsvPath || !outputPath || !previewDir) {
  throw new Error("Usage: build_lca_role_review_workbook.mjs <soc.csv> <raw.csv> <output.xlsx> <preview-dir>");
}

const workbook = Workbook.create();
await workbook.fromCSV(await fs.readFile(socCsvPath, "utf8"), { sheetName: "SOC大类汇总" });
await workbook.fromCSV(await fs.readFile(rawCsvPath, "utf8"), { sheetName: "RawJob_SOC明细" });

const soc = workbook.worksheets.getItem("SOC大类汇总");
const raw = workbook.worksheets.getItem("RawJob_SOC明细");
const socRows = soc.getUsedRange().rowCount;
const rawRows = raw.getUsedRange().rowCount;

for (const sheet of [soc, raw]) {
  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(1);
}

soc.getRange(`A1:M${socRows}`).format.font = { name: "Aptos", size: 10 };
soc.getRange("A1:M1").format = {
  fill: "#17324D",
  font: { name: "Aptos Display", size: 10, bold: true, color: "#FFFFFF" },
  rowHeight: 32,
  wrapText: true,
  verticalAlignment: "center",
};
soc.getRange(`C2:C${socRows}`).dataValidation = {
  rule: { type: "list", values: ["", "target", "non_target", "review"] },
};
soc.getRange(`E2:H${socRows}`).format.numberFormat = "#,##0";
soc.getRange(`K2:M${socRows}`).format.numberFormat = "$#,##0";
soc.getRange(`I2:J${socRows}`).format.numberFormat = "yyyy-mm-dd";
for (const [col, width] of [[0, 120], [1, 300], [2, 130], [3, 120], [4, 95], [5, 105], [6, 105], [7, 120], [8, 120], [9, 120], [10, 130], [11, 150], [12, 130]]) {
  soc.getRangeByIndexes(0, col, socRows, 1).format.columnWidthPx = width;
}
soc.tables.add(`A1:M${socRows}`, true, "SOCSummary").style = "TableStyleMedium2";

raw.getRange(`A1:N${Math.min(rawRows, 5000)}`).format.font = { name: "Aptos", size: 10 };
raw.getRange("A1:N1").format = {
  fill: "#244062",
  font: { name: "Aptos Display", size: 10, bold: true, color: "#FFFFFF" },
  rowHeight: 32,
  wrapText: true,
  verticalAlignment: "center",
};
raw.getRange(`D2:D${rawRows}`).dataValidation = {
  rule: { type: "list", values: ["", "target", "non_target", "review"] },
};
raw.getRange(`F2:H${rawRows}`).format.numberFormat = "#,##0";
raw.getRange(`L2:N${rawRows}`).format.numberFormat = "$#,##0";
raw.getRange(`J2:K${rawRows}`).format.numberFormat = "yyyy-mm-dd";
for (const [col, width] of [[0, 120], [1, 280], [2, 320], [3, 130], [4, 120], [5, 95], [6, 105], [7, 105], [8, 460], [9, 120], [10, 120], [11, 130], [12, 150], [13, 130]]) {
  raw.getRangeByIndexes(0, col, rawRows, 1).format.columnWidthPx = width;
}
raw.getRange(`A1:N${Math.min(rawRows, 2000)}`).format.wrapText = true;

const guide = workbook.worksheets.add("说明");
guide.showGridLines = false;
guide.getRange("A1:F1").merge();
guide.getRange("A1").values = [["JobPush LCA / SOC 初始职业标注复审"]];
guide.getRange("A1:F1").format = {
  fill: "#17324D",
  font: { name: "Aptos Display", size: 20, bold: true, color: "#FFFFFF" },
  rowHeight: 46,
  verticalAlignment: "center",
};
guide.getRange("A3:B9").values = [
  ["SOC 大类行数", socRows - 1],
  ["Raw job / SOC 明细行数", rawRows - 1],
  ["数据粒度", "聚合覆盖全部 LCA；不是 78 万明细行"],
  ["请编辑", "是否目标_请填写"],
  ["可选值", "target / non_target / review / 空白"],
  ["当前 target 来源", "config/target_soc_roles.csv"],
  ["生成日期", new Date()],
];
guide.getRange("A3:A9").format = { fill: "#E9EFF6", font: { bold: true, color: "#17324D" } };
guide.getRange("A3:B9").format.borders = { preset: "inside", style: "thin", color: "#D0D5DD" };
guide.getRange("B9").format.numberFormat = "yyyy-mm-dd";
guide.getRange("A11:F13").merge(true);
guide.getRange("A11").values = [["建议先看 SOC大类汇总，确认哪些 SOC 是目标；再到 RawJob_SOC明细 看 SOC 下面具体 raw title 是否需要拆规则。"]];
guide.getRange("A12").values = [["Dashboard 的 target_role_score 只看 SOC code 是否命中 target_soc_roles；官网职位推荐再由 job_title_labels / profile-title-rules-v2 / hard exclusions 细分。"]];
guide.getRange("A13").values = [["如果你改了这一份标注，下一步应该生成 migration 更新 jobpush.target_soc_roles，并重新 refresh company_targets_consolidated。"]];
guide.getRange("A11:F13").format = { fill: "#FFF6D8", font: { color: "#624A00" }, wrapText: true };
guide.getRange("A1:F13").format.font = { name: "Aptos", size: 11 };
guide.getRange("A1:F1").format.font = { name: "Aptos Display", size: 20, bold: true, color: "#FFFFFF" };
guide.getRange("A1:A13").format.columnWidthPx = 180;
guide.getRange("B1:F13").format.columnWidthPx = 180;

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

for (const [sheetName, range] of [["说明", "A1:F13"], ["SOC大类汇总", "A1:M18"], ["RawJob_SOC明细", "A1:N18"]]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(path.join(previewDir, `${sheetName}.png`), new Uint8Array(await preview.arrayBuffer()));
}

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({ outputPath, socRows, rawRows }));
