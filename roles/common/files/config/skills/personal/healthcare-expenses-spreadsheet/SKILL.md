---
name: healthcare-expenses-spreadsheet
description: >
  Add healthcare expenses to the Unreimbursed Health Care Expenses spreadsheet.
  Use when the user asks to add health care expenses, EOB line items, or medical/pharmacy
  costs to the spreadsheet.
---

# Healthcare Expenses Spreadsheet

Add healthcare expenses from a source document (explanation of benefits, receipt, invoice, etc.)
into the `Unreimbursed Health Care Expenses.xlsx` spreadsheet.

## Prerequisites Check

Before doing anything else, verify that the current directory contains:

1. A file named exactly `Unreimbursed Health Care Expenses.xlsx`
2. At least one other file (the source document containing the expenses)

If either is missing, stop and tell the user what's missing and what you expected to find.

## Gathering Information

Read the source document and extract expense line items. For each line item you need:

- **Date**: The service or fill date
- **Provider**: The provider or pharmacy name
- **Amount**: The patient's out-of-pocket cost (NOT the plan-paid amount — the amount the
  patient actually paid or owes)
- **Notes**: A brief description of the service or item (e.g., drug name and dosage, type of
  visit)

You also need URLs for the Statement and Receipt columns. These may be the same URL or
different URLs. If the user hasn't already provided them, ask for them before making any
changes to the spreadsheet.

## Spreadsheet Format

Each row in the spreadsheet has these columns:

| Column | Field     | Format |
|--------|-----------|--------|
| A      | Date      | Right-aligned, `m/d/yyyy` format (e.g., `1/15/2026`) |
| B      | Provider  | Text |
| C      | Amount    | Right-aligned, currency (the out-of-pocket cost) |
| D      | Statement | `=HYPERLINK("<url>","Link")` |
| E      | Receipt   | `=HYPERLINK("<url>","Link")` |
| F      | Notes     | Brief description of the service or item |

## Process

1. Read the existing spreadsheet to find the last row of data
2. Read the source document and extract all expense line items
3. Present the extracted line items to the user for review before modifying the spreadsheet
4. If Statement and/or Receipt URLs have not been provided, ask for them
5. Append new rows after the last existing data row
6. Ensure Date (column A) and Amount (column C) are right-aligned to match existing rows
7. After writing, confirm what was added
