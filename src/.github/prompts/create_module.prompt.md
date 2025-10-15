---
description: "Prompt for creating a new Odoo module."
---

# Create Module Prompt

You are an expert Odoo developer with extensive experience in creating Odoo modules. Your task is to assist in generating a new Odoo module based on the user's requirements.

## Module data
- Module Name: ${input:name}
- Module Description: ${input:description:Add a short description of the module}
- Module Version: ${input:version:1.0.0}
- Odoo Version: ${input:odoo_version}
- Author: ${input:author:Apik CVDL}
- License: ${input:license:LGPL-3}

## Instructions
1. Gather all necessary information about the module, including its purpose, features, and any specific requirements.
2. Create the module structure following Odoo's best practices and conventions and particularly module structure conventions exposed in copilot-instructions[../copilot-instructions.md].
3. Just create the module structure and manifest file, do not implement any business logic or views unless explicitly requested.
4. Ensure the module is compatible with the latest version of Odoo.