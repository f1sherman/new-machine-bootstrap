---
name: healthcare-expenses-spreadsheet
description: >
  Add healthcare expenses to the Unreimbursed Health Care Expenses spreadsheet.
  Use when the user asks to add health care expenses, EOB line items, or medical/pharmacy
  costs to the spreadsheet.
---

# Healthcare Expenses Spreadsheet

Add healthcare expenses from a source document into the `Unreimbursed Health Care Expenses.xlsx` spreadsheet.

## Prerequisites

Check the current directory first.

- `Unreimbursed Health Care Expenses.xlsx` must exist.
- At least one other file must exist as the source document.
- If multiple candidate source files exist and the intended one is unclear, ask the user before proceeding.

If either is missing, stop and state what is missing and what was expected.

## Extract Data

Read the source document and extract expense line items. For each line item you need:

- **Date**: The service or fill date
- **Provider**: The provider or pharmacy name
- **Amount**: The patient's out-of-pocket cost, not the plan-paid amount.
- **Notes**: Brief description of the service or item, such as drug name and dosage or visit type.

Get URLs for the Statement and Receipt columns.
They may be the same URL or different URLs.
If they are missing, ask before changing the spreadsheet.

## Spreadsheet Format

Each row uses these columns:

| Column | Field     | Format |
|--------|-----------|--------|
| A      | Date      | Right-aligned, `m/d/yyyy` format (e.g., `1/15/2026`) |
| B      | Provider  | Text |
| C      | Amount    | Right-aligned, currency (the out-of-pocket cost) |
| D      | Statement | `=HYPERLINK("<url>","Link")` |
| E      | Receipt   | `=HYPERLINK("<url>","Link")` |
| F      | Notes     | Brief description of the service or item |

## Process

1. Read the spreadsheet and find the last data row.
2. Read the source document and extract all expense line items.
3. Show the extracted line items to the user for review before modifying the spreadsheet.
4. Ask for Statement and/or Receipt URLs if they have not been provided.
5. Append new rows after the last existing data row.
6. Keep Date in column A and Amount in column C right-aligned to match existing rows.
7. After writing, confirm what was added.
