# OpenCode

OpenCode es un agente de código abierto que te ayuda a escribir código tanto desde la terminal como desde el IDE o su aplicación de escritorio. El potencial de OpenCode, entre otras cosas, está en la posibilidad de utilizar distintos proveedores de LLM, incluyendo modelos locales y modelos gratuitos, entre los que destaca **Nemotron 3 Ultra Free**. Para ver los modelos gratuitos tenéis el siguiente link https://opencode.ai/v2/docs/console/models/ y recordar que con el comando /model podréis seleccionar el modelo que queráis y con /connect podréis incluir vuestra suscripción para poder a acceder a vuestros modelos de pago.

Además, cuenta con una serie de herramientas que amplían considerablemente las capacidades de los modelos utilizados, como la integración con **LSPs (Language Server Protocol)**, que permiten al agente comprender mejor la estructura del proyecto, navegar por el código y detectar errores de forma más precisa. OpenCode también permite trabajar con múltiples sesiones y ejecutar varios agentes en paralelo, facilitando la división de tareas complejas. A esto se suma la posibilidad de centralizar MCPs, Skills y otras herramientas reutilizables, de forma que puedan ser compartidas entre distintos modelos y proveedores sin depender de un ecosistema concreto.

OpenCode incorpora además comandos propios para controlar y preparar el contexto de trabajo. Por ejemplo, `/init` permite inicializar el agente dentro de un proyecto y generar las instrucciones necesarias para que comprenda mejor su estructura, convenciones y características principales. Este sistema de comandos facilita tareas como preparar el contexto del repositorio, gestionar sesiones o ejecutar determinadas acciones del agente directamente desde la interfaz, reduciendo la necesidad de explicar repetidamente al modelo cómo está organizado el proyecto.

Por medio de la tecla `Tab` podremos cambiar entre los distintos modos de trabajo, pudiendo desactivar temporalmente su capacidad de realizar cambios en el código mediante el modo **Plan**. Este modo resulta bastante útil cuando simplemente queremos que analice el proyecto, nos proponga una solución o nos explique qué cambios realizaría antes de aplicarlos. Por otro lado, tenemos el modo **Build**, pensado ya para trabajar directamente sobre el proyecto y permitir que el agente realice modificaciones.

Además, nosotros podremos añadir nuestras propias instrucciones, comandos, Skills o herramientas para adaptar considerablemente el comportamiento del agente a nuestro flujo de trabajo. Esto permite, por ejemplo, definir ciertas reglas para un proyecto, reutilizar prompts que utilizamos habitualmente o darle acceso a MCPs concretos dependiendo de lo que necesitemos hacer.

Con el comando `/undo` podremos deshacer los cambios que haya creado la IA y, además, incluso podemos compartir conversaciones que tengamos con OpenCode a través del comando `/share`.

## Privacidad

También es importante hablar de privacidad. OpenCode indica que no almacena ni el código ni los datos de contexto, ya que el procesamiento se realiza localmente o mediante llamadas directas a la API del proveedor que estemos utilizando.

En el siguiente enlace se explica cómo podría utilizarse OpenCode dentro de un entorno empresarial:

https://opencode.ai/docs/es/enterprise/

Otro punto positivo por el cual OpenCode es bastante valorado es su sistema de **compactación del contexto**. OpenCode puede gestionar el contexto cuando este se acerca al límite del modelo, reemplazando conversaciones antiguas por un resumen y manteniendo los mensajes más recientes.

La compactación ayuda principalmente a reducir la cantidad de tokens que OpenCode tiene que volver a enviar al modelo en cada petición durante una sesión larga. Esto permite continuar trabajando durante más tiempo sin arrastrar constantemente toda la conversación original.

## Configuración

Para configurar OpenCode hacemos uso de archivos en formato **JSON** o **JSONC**, siendo bastante sencillo modificar su comportamiento y adaptarlo a nuestro flujo de trabajo.

La configuración puede definirse tanto a nivel de proyecto, dentro del directorio `.opencode`, como de forma global mediante:

```text
~/.config/opencode
```

Esto nos permite mantener una configuración general y sobrescribirla cuando algún proyecto necesite ajustes específicos.

En la siguiente URL podemos consultar el esquema de configuración de OpenCode, donde aparecen las distintas propiedades disponibles y la estructura que puede tener nuestro archivo de configuración:

https://opencode.ai/config.json

También podemos consultar toda la documentación relativa a la configuración aquí:

https://opencode.ai/docs/es/config/

Si nos fijamos, una de las configuraciones que ofrece esta herramienta es la posibilidad de definir **agentes especializados** para tareas específicas a través de la opción `agent`.

Estos agentes pueden disponer de su propio modelo, prompt, permisos y herramientas disponibles, permitiéndonos crear distintos perfiles dependiendo de la tarea que queramos realizar.

Por ejemplo, podríamos crear un agente dedicado exclusivamente a realizar revisiones de código, utilizando un modelo concreto y quitándole los permisos de escritura y edición para evitar que pueda modificar archivos accidentalmente.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "code-reviewer": {
      "description": "Reviews code for best practices and potential issues",
      "model": "anthropic/claude-sonnet-4-5",
      "prompt": "You are a code reviewer. Focus on security, performance, and maintainability.",
      "tools": {
        "write": false,
        "edit": false
      }
    }
  }
}
```

Aparte de todo esto, por si fuera poco, OpenCode también nos ofrece un sistema de **plugins**, que no debemos confundir con los **Skills**.

Mientras que un Skill no es más que un paquete de instrucciones reutilizables que guía al modelo sobre cómo realizar una determinada tarea, un plugin permite extender OpenCode como aplicación.

OpenCode también permite definir instrucciones globales para el modelo mediante la opción `instructions` dentro de `opencode.json`.

Es decir, mediante plugins podemos añadir nuevas herramientas, integrarnos con servicios externos, reaccionar a determinados eventos o modificar parte del comportamiento de OpenCode.

