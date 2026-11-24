# Templates

The 25 built-in templates are defined in code, in `Sources/Core/TemplateLibrary.swift`, so they are
type-checked, validated by the test suite (`TemplateTests`) and always match the renderer.

This folder holds **example widget files** in the shareable `.wfwidget` format. Import them from
*Marketplace → Import…* (or drop them on the Marketplace page) to see the import review sheet, and use
them as starting points for your own:

| File | Shows |
| --- | --- |
| `hello-world.wfwidget` | Declarative layout, a `{{state}}` placeholder and a state-changing button. No permissions. |
| `uptime-script.wfwidget` | The JavaScript SDK: `update`, `render`, `context.system`, `context.storage`. Its script stays disabled until you trust it. |

Every file here is imported and validated by `ExampleFilesTests`.
