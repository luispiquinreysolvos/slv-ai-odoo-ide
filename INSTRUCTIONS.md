# Instalación y configuración de Solvos para OpenCode

Estos instaladores preparan OpenCode con una configuración orientada al desarrollo de software. Además de instalar la aplicación, incorporan tres agentes con distintas capacidades, servidores MCP, el plugin Ponytail y skills especializadas para trabajar con Odoo. El objetivo es disponer de un entorno preparado tanto para tareas sencillas sobre archivos locales como para trabajos que requieren documentación externa, memoria persistente, pruebas en el navegador o colaboración entre subagentes.

Por cierto, para poder trabajar con OpenCode en VSCode emplear la siguiente extensión: https://marketplace.visualstudio.com/items?itemName=sst-dev.opencode. En terminal simplemente escribís el comando opencode y os debería de abrir, eso si recordar hacer un refresh de la terminal una vez instalado todo.

## Instalación en Windows

Para ejecutar el instalador de Windows necesitáis **PowerShell 7 o superior**. Windows PowerShell 5.1, incluido en muchas instalaciones de Windows, no cumple este requisito. Podéis instalar PowerShell 7 mediante el siguiente comando:

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Una vez terminada la instalación, abrid una terminal nueva y ejecutad `pwsh`. Al iniciarse, aparecerá la versión instalada, que debe ser **7.X.X**. Es importante distinguir los dos comandos: `powershell` inicia Windows PowerShell 5.1, mientras que `pwsh` inicia PowerShell 7. Aunque ya estéis dentro de PowerShell 7, escribir un comando que empiece por `powershell` volverá a ejecutar el instalador con la versión antigua y provocará un error.

Desde la carpeta donde habéis descargado el proyecto, ejecutad el instalador con este comando:

```powershell
pwsh -ExecutionPolicy Bypass -File .\install.ps1
```

La opción `-ExecutionPolicy Bypass` se aplica al proceso que ejecuta el instalador y permite evitar bloqueos derivados de la política de ejecución de scripts.

**Para seguir la instalación descrita en esta guía, abrid la terminal como administrador**, especialmente cuando sea necesario instalar dependencias en el equipo.

## Instalación en Linux

En Linux, el instalador correspondiente es `install.sh`. Antes de ejecutarlo, debéis aseguraros de que tiene permisos de ejecución. Desde la carpeta del proyecto, podéis concederlos mediante el siguiente comando:

```bash
chmod +x ./install.sh
```

Después, iniciad la instalación:

```bash
./install.sh
```

Seguid las indicaciones que aparezcan en la terminal y revisad cualquier mensaje de error antes de continuar. Si la instalación se interrumpe, conservad la salida del comando para identificar qué dependencia o paso necesita atención.

## Carpeta autorizada para el MCP Filesystem

Durante la instalación se os solicitará una **ruta absoluta a una carpeta existente**. Esta ruta se utiliza para configurar el MCP Filesystem, que permite a la IA acceder a los archivos y directorios incluidos dentro de la carpeta autorizada. Elegid una ubicación que contenga los proyectos con los que vais a trabajar habitualmente, teniendo en cuenta que autorizar una carpeta también permite acceder a sus subcarpetas.

Por ejemplo, si todos vuestros proyectos están dentro de `C:\Users\vuestro_usuario\Proyectos`, podéis autorizar esa carpeta. Si trabajáis en Linux, una ruta equivalente podría ser `/home/vuestro_usuario/proyectos`. Un proyecto situado fuera de la ruta autorizada no podrá consultarse mediante este MCP, aunque otras herramientas de OpenCode tengan sus propios permisos de acceso.

La ruta queda guardada en la configuración como una ubicación absoluta. **No necesitáis situaros siempre en esa carpeta para iniciar OpenCode**: lo habitual es abrirlo desde el directorio del proyecto en el que vais a trabajar. Si el MCP muestra una carpeta autorizada distinta de la que introdujisteis, será necesario comprobar la configuración que está usando la sesión y los directorios permitidos por el servidor en ejecución.

## Agentes incluidos

La configuración incorpora tres agentes principales: **solvos-ultralight**, **solvos-standard** y **solvos-complete**. Se añaden a los agentes Build y Plan de OpenCode, y podéis cambiar entre los agentes disponibles mediante la tecla **Tab**.

Los tres perfiles comparten una forma de trabajo centrada en investigar antes de modificar, respetar la estructura del proyecto y realizar cambios concretos que respondan a la petición. También deben verificar el resultado con las comprobaciones disponibles y explicar cualquier limitación cuando no sea posible confirmar completamente que una solución funciona.

**solvos-ultralight** está pensado para tareas que pueden resolverse con las herramientas locales de OpenCode. No utiliza MCPs, LSP, skills ni subagentes, por lo que ofrece un conjunto de capacidades más reducido. Es una opción adecuada cuando basta con inspeccionar archivos, comprender código y realizar modificaciones acotadas.

**solvos-standard** incorpora documentación externa, memoria persistente, LSP y skills. Este perfil puede consultar Context7 y DeepWiki, recuperar contexto mediante Engram y aprovechar herramientas de análisis del código. Está orientado a trabajos que requieren comprender mejor un proyecto o consultar información sobre sus dependencias.

**solvos-complete** amplía esas capacidades con el MCP Filesystem, automatización del navegador mediante Playwright y uso de subagentes. Está preparado para tareas que requieren acceso a la carpeta autorizada, comprobaciones sobre aplicaciones web o reparto del trabajo entre agentes.

## Plugin Ponytail

El instalador incluye globalmente el plugin **Ponytail**, orientado a reducir la sobreingeniería y favorecer implementaciones ajustadas a lo que realmente necesita la tarea. Su propósito es ayudar a que los agentes eviten añadir abstracciones, estructuras o código innecesarios cuando una solución más directa resulta suficiente.

Este enfoque busca mantener los cambios fáciles de revisar y reducir trabajo y consumo de tokens innecesarios. El ahorro concreto dependerá de la tarea y del comportamiento del agente.

Repositorio de GitHub: [dietrichgebert/ponytail](https://github.com/dietrichgebert/ponytail).

## Servidores MCP

Los servidores MCP amplían las herramientas que puede utilizar el agente. La configuración completa incluye cinco: **Filesystem, Playwright, Context7, DeepWiki y Engram**. Su disponibilidad depende del perfil seleccionado: el agente standard utiliza Context7, DeepWiki y Engram, mientras que el agente complete incorpora también Filesystem y Playwright.

### Filesystem

Filesystem permite a la IA consultar y modificar archivos dentro de la carpeta autorizada durante la instalación. Proporciona herramientas específicas para trabajar con archivos y directorios, complementando las herramientas nativas de OpenCode.

Su alcance depende de los directorios que tenga autorizados el servidor en ejecución. Por ello, seleccionar correctamente la ruta durante la instalación es importante para que el agente pueda trabajar con los proyectos previstos.

### Playwright

Playwright permite interactuar con navegadores web de forma automatizada. El agente puede navegar por páginas, pulsar botones, rellenar formularios y comprobar el comportamiento de una interfaz. Estas capacidades resultan útiles para reproducir errores y realizar verificaciones de extremo a extremo sobre aplicaciones web.

El instalador configura el navegador en modo **headless**, sin una ventana visible, y con una sesión aislada. Si falta el navegador necesario para trabajar, podéis pedir al agente que utilice la herramienta `browser_install` del MCP Playwright.

### Context7

Context7 proporciona acceso a documentación de librerías, frameworks, SDKs y otras tecnologías. Ayuda al agente a consultar cómo se utiliza una API o qué comportamiento corresponde a una versión concreta de una dependencia.

Es especialmente útil cuando el código depende de herramientas que cambian con el tiempo. Para obtener respuestas adecuadas, conviene que el agente identifique primero la versión utilizada por el proyecto y consulte documentación compatible con ella.

### DeepWiki

DeepWiki permite consultar información sobre repositorios públicos y comprender su estructura, arquitectura e implementación. Puede ayudar a investigar cómo funciona una dependencia o cómo se organiza un proyecto externo.

Esta información complementa la inspección del proyecto local. Si existen diferencias entre lo descrito sobre un repositorio externo y el código realmente instalado, el agente debe tener en cuenta la versión y los archivos con los que está trabajando.

### Engram

Engram proporciona memoria persistente para guardar y recuperar información relevante entre sesiones. Puede conservar decisiones tomadas durante el desarrollo, problemas resueltos y contexto que resulte útil para continuar trabajando en un proyecto.

Gracias a esa memoria, el agente puede recuperar información previamente registrada y reducir la necesidad de repetir investigaciones. Aun así, debe contrastar los datos guardados con el estado actual del proyecto cuando puedan haber cambiado.

| Agente | Filesystem | Playwright | Context7 | DeepWiki | Engram |
| --- | :---: | :---: | :---: | :---: | :---: |
| `solvos-ultralight` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `solvos-standard` | ❌ | ❌ | ✅ | ✅ | ✅ |
| `solvos-complete` | ✅ | ✅ | ✅ | ✅ | ✅ |

## Skills de Odoo

El instalador incorpora un conjunto de **skills especializadas en Odoo** para los perfiles standard y complete. Las skills son instrucciones y recursos que orientan al agente en tareas concretas, aportando convenciones y referencias que puede consultar durante el trabajo.

El conjunto instalado incluye **odoo-workflow**, **odoo-commit** y referencias para **Odoo 16, 17, 18 y 19**. Estas últimas cubren áreas como modelos Python y ORM, vistas XML, OWL y JavaScript, plantillas e informes QWeb, seguridad, controladores, migraciones, pruebas, traducciones y rendimiento.

Las skills de workflow y commit aportan pautas para el flujo de desarrollo y la preparación de commits. Las referencias por versión ayudan a adaptar el trabajo a la versión de Odoo utilizada por el proyecto. Antes de aplicar esas indicaciones, el agente debe comprobar la versión real y revisar el código existente.

El instalador utiliza una revisión fijada del repositorio de origen, de forma que el contenido descargado corresponde a una versión concreta de las skills.

Repositorio de GitHub: [unclecatvn/agent-skills](https://github.com/unclecatvn/agent-skills).

## Iniciar OpenCode

Una vez completada la instalación, abrid una terminal en la carpeta del proyecto y elegid el agente que queráis utilizar:

```bash
opencode --agent solvos-ultralight
```

```bash
opencode --agent solvos-standard
```

```bash
opencode --agent solvos-complete
```
