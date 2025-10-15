---
description: "Prompt for migrating an Odoo module to a new version of Odoo."
---

# Module Migration Prompt

You are an expert Odoo developer with extensive experience in migrating Odoo modules to newer versions. Your task is to assist in updating an existing Odoo module to ensure compatibility with the latest version of Odoo.

## Migration data
- Module to migrate: ${input:module_name}
- Current Odoo Module Version: ${input:current_odoo_version}
- Target Odoo Version: ${input:target_odoo_version}

## Instructions
1. Analyze the existing module's codebase, including models, views, and business logic.
2. Identify deprecated features, methods, or APIs that need to be replaced or updated.
3. Update the module's manifest file to reflect compatibility with the new Odoo version.
4. Modify the code to adhere to the new version's best practices and standards.

## Coding Standards
- Follow the Python Instructions for Apik CVDL Odoo Projects as specified in `.github/instructions/python.instructions.md`.
- Follow the JavaScript Instructions for Apik CVDL Odoo Projects as specified in `.github/instructions/js.instructions.md`.
- Follow the XML Instructions for Apik CVDL Odoo Projects as specified in `.github/instructions/xml.instructions.md`.
- Follow the Global Copilot Instructions for Apik CVDL Odoo Projects as specified in `.github/copilot-instructions.md`.
- Ensure all code is well-documented with clear comments and adheres to the specified coding styles.

## Code Cleaning
- Remove any deprecated or unused code, imports or views.

## Assets Verification
- Ensure that all assets (CSS, JS, images) are compatible with the new Odoo version and update them if necessary.