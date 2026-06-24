#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const [csvPath, outputPath, previewDir] = process.argv.slice(2);
if (!csvPath || !outputPath || !previewDir) {
  throw new Error("Usage: build_job_title_review_workbook.mjs <input.csv> <output.xlsx> <preview-dir>");
}

const csvText = await fs.readFile(csvPath, "utf8");
const workbook = await Workbook.fromCSV(csvText, { sheetName: "职位审核" });
const review = workbook.worksheets.getItem("职位审核");
const used = review.getUsedRange();
const rowCount = used.rowCount;

review.showGridLines = false;
review.freezePanes.freezeRows(1);
review.getRange(`A1:K${rowCount}`).format.font = { name: "Aptos", size: 10 };
review.getRange("A1:K1").format = {
  fill: "#17324D",
  font: { name: "Aptos Display", size: 10, bold: true, color: "#FFFFFF" },
  rowHeight: 32,
  wrapText: true,
  verticalAlignment: "center",
};
review.getRange(`A2:K${rowCount}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#E6EAF0" },
};
review.getRange(`C2:D${rowCount}`).format.numberFormat = "#,##0";
review.getRange(`I2:I${rowCount}`).dataValidation = {
  rule: { type: "list", values: ["target", "non_target", "review"] },
};
review.getRange(`I2:I${rowCount}`).conditionalFormats.add("containsText", {
  text: "target", format: { fill: "#DDF4E7", font: { color: "#176B3A", bold: true } },
});
review.getRange(`I2:I${rowCount}`).conditionalFormats.add("containsText", {
  text: "non_target", format: { fill: "#FDE7E7", font: { color: "#9B1C1C", bold: true } },
});
review.getRange(`I2:I${rowCount}`).conditionalFormats.add("containsText", {
  text: "review", format: { fill: "#FFF2CC", font: { color: "#7A4D00", bold: true } },
});

const widths = [210, 240, 90, 90, 260, 180, 120, 260, 150, 180, 260];
for (let index = 0; index < widths.length; index += 1) {
  review.getRangeByIndexes(0, index, rowCount, 1).format.columnWidthPx = widths[index];
}
review.getRange(`A2:K${rowCount}`).format.verticalAlignment = "top";
review.getRange(`A2:K${rowCount}`).format.rowHeight = 24;
review.getRange(`E2:F${rowCount}`).format.wrapText = true;
review.getRange(`I2:K${rowCount}`).format.wrapText = true;
review.tables.add(`A1:K${rowCount}`, true, "JobTitleReviewTable").style = "TableStyleMedium2";

const guide = workbook.worksheets.add("说明");
guide.showGridLines = false;
guide.getRange("A1:F1").merge();
guide.getRange("A1").values = [["JobPush 职位审核批次"]];
guide.getRange("A1:F1").format = {
  fill: "#17324D",
  font: { name: "Aptos Display", size: 20, bold: true, color: "#FFFFFF" },
  rowHeight: 44,
  verticalAlignment: "center",
};
guide.getRange("A3:B6").values = [
  ["批次职位数", null],
  ["已填写", null],
  ["未填写", null],
  ["生成日期", new Date()],
];
guide.getRange("B3").formulas = [[`=COUNTA('职位审核'!$A$2:$A$${rowCount})`]];
guide.getRange("B4").formulas = [[`=COUNTIF('职位审核'!$I$2:$I$${rowCount},"target")+COUNTIF('职位审核'!$I$2:$I$${rowCount},"non_target")+COUNTIF('职位审核'!$I$2:$I$${rowCount},"review")`]];
guide.getRange("B5").formulas = [["=B3-B4"]];
guide.getRange("B6").format.numberFormat = "yyyy-mm-dd";
guide.getRange("A3:A6").format = { fill: "#E9EFF6", font: { bold: true, color: "#17324D" } };
guide.getRange("A8:F8").merge();
guide.getRange("A8").values = [["只需要编辑“职位审核”中的三列：人工判断、标准岗位、判断原因/备注。人工判断可选 target / non_target / review。其余列用于证据和排序，请勿修改 normalized_title。"]];
guide.getRange("A8:F8").format = { fill: "#FFF6D8", font: { color: "#624A00" }, wrapText: true, rowHeight: 58 };
guide.getRange("A10:B13").values = [
  ["target", "适合当前求职目标"],
  ["non_target", "明确不适合，例如 Lead/Principal/硬件/ML 模型岗位"],
  ["review", "仅凭标题仍无法判断"],
  ["排序", "按活跃职位数、公司数从高到低"],
];
guide.getRange("A10:A13").format = { font: { bold: true, color: "#17324D" } };
guide.getRange("A3:B6").format.borders = { preset: "outside", style: "thin", color: "#CBD5E1" };
guide.getRange("A10:B13").format.borders = { preset: "inside", style: "thin", color: "#E6EAF0" };
guide.getRange("A1:F13").format.font = { name: "Aptos", size: 11 };
guide.getRange("A1:F1").format.font = { name: "Aptos Display", size: 20, bold: true, color: "#FFFFFF" };
guide.getRange("A1:A13").format.columnWidthPx = 160;
guide.getRange("B1:B13").format.columnWidthPx = 420;

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

for (const [sheetName, range] of [["说明", "A1:F13"], ["职位审核", "A1:K18"]]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(
    path.join(previewDir, `${sheetName}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

const inspection = await workbook.inspect({
  kind: "table",
  sheetId: "职位审核",
  range: "A1:K8",
  include: "values,formulas",
  tableMaxRows: 8,
  tableMaxCols: 11,
});
console.log(inspection.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);
