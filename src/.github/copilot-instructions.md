# Global Copilot Instructions for Apik CVDL Odoo Projects
---

## Key Architecture Patterns

### Module Structure Convention
```
module_name/
├── __manifest__.py          # Dependencies, data files, license: LGPL-3
├── models/__init__.py       # Import all model files
├── views/                   # XML view inheritance using xpath
├── security/               # ir.model.access.csv, groups.xml, ir_rule.xml
├── data/                   # Default data, server actions, cron jobs
├── i18n/                   # Translation files (.po)      
└── wizards/               # Transient models for user interactions
```

### Model Inheritance Pattern
- Always inherit existing Odoo models using `_inherit = "model.name"`
- Override `create()` and `write()` methods for custom business logic
- Don't forget to call `super()` and use `@override` in overridden methods

#### Decorators
- Use `@api.model` for methods that do not depend on record data
- Use `@api.onchange()` for dynamic field updates in forms
- Use `@api.depends()` for computed fields with proper invalidation
- Use `@api.constrains()` for field validation rules
- Use `@api.returns()` to specify return types for methods
- Don't use `@api.multi`, it's deprecated


### View Inheritance Strategy
- Use xpath expressions to modify existing views: `xpath expr="//field[@name='field_name']" position="replace|after|before|attributes"`
- Conditional visibility with `invisible` attributes: `<attribute name="invisible" separator="or" add="type != 'contact'"></attribute>`
- Widget customization: `widget="many2one"`, `widget="radio"`, `widget="badge"`, `options="{'horizontal': true}"`

### Security Implementation
- Define custom groups in `security/groups.xml`
- Use `user_has_groups()` for conditional logic in models
- Set access rights in `ir.model.access.csv` and record rules in `security/ir_rule.xml`


## Development Workflows

### Adding New Modules
1. Create module directory with standard structure
2. Define `__manifest__.py` with proper dependencies and LGPL-3 license
3. Import models in `models/__init__.py`
4. Add security configurations before data files in manifest

## External Dependencies & Integrations

### Dependencies Workflow
- Always ask the user before adding new dependencies
- Adding dependencies in `requirements.txt` and `__manifest__.py`

### Recommended Libraries
- Use paramiko for SSH, SFTP, and file transfer operations

### Versioning
- Populate CHANGELOG.md with changements 
- The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Documentation
- All documentation needs are explained in specific instructions files like `python.instructions.md`, `js.instructions.md`, `xml.instructions.md`

## User Interactions
- Ask questions if you are unsure about the implementation details, design choices, or need clarification on the requirements
- Always answer in the same language as the question, but use english for the generated content like code, comments or docs

## Traduction
- Traduction files are in the `i18n/` folder
- Use the command below to generate or update traduction files:
```bash
python odoo-bin --i18n-export=module/i18n/fr.po -l fr -m module_name
```
- Use `fr` for French, `en` for English, `es` for Spanish, etc.
- Always ask the user if a new language is needed before adding it
- Use English for all names and comments in the code

## Data
- Use data/ for default data, server actions, cron jobs
- Use demo/ for demo data only if specified in the manifest
- Always ask the user if demo data is needed before adding it
- Prefer XML over CSV format for data files
- Use CSV only for large datasets or when data is tabular
- Always ask the user if a data file is needed before adding it
