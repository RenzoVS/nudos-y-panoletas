# Nudos y Pañoletas

Foro de juegos para reuniones scout. Los dirigentes publican juegos y otros los encuentran filtrando por rama, nivel de riesgo, tipo (activo, semiactivo o pasivo), cantidad de scouts y si son aplicativos.

## Qué hay en cada archivo

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La estructura de la página: cabecera, buscador, lista y formularios. |
| `css/estilos.css` | Colores, letras y diseño. Los colores de la marca están al inicio. |
| `js/config.js` | Los datos de conexión con Supabase (URL y publishable key). |
| `js/app.js` | La lógica: cargar, filtrar, mostrar y publicar juegos. |
| `supabase/esquema.sql` | La tabla de juegos y las reglas de seguridad de la base de datos (versión actual). |
| `supabase/migraciones/` | Cada cambio que se le hizo a la base de datos, con su fecha. |
| `img/` | Logo y favicon. |

Cada archivo tiene comentarios que explican qué hace cada parte.

## Cómo funciona

1. La página pide a Supabase los juegos con estado `aprobado`.
2. Los filtros y la búsqueda funcionan en el navegador, sin volver a consultar la base de datos.
3. Cuando alguien publica un juego, se guarda con estado `pendiente` y no aparece hasta que lo apruebas.

## Publicar la página (GitHub + Vercel)

### 1. Subir los archivos a GitHub
1. Crea una cuenta gratis en [github.com](https://github.com).
2. Arriba a la derecha: **+** > **New repository**. Nombre: `nudos-y-panoletas`. Déjalo **Public** y crea.
3. En la página del repositorio, haz clic en **uploading an existing file**.
4. Arrastra **el contenido** de la carpeta (index.html, css, js, img, supabase, README.md), no la carpeta entera.
5. Abajo, **Commit changes**.

### 2. Publicar con Vercel
1. Entra a [vercel.com](https://vercel.com) y elige **Continue with GitHub**.
2. **Add New...** > **Project** > busca `nudos-y-panoletas` > **Import**.
3. En "Framework Preset" deja **Other**. No cambies nada más.
4. **Deploy**. En menos de un minuto tendrás una dirección como `nudos-y-panoletas.vercel.app`.

### 3. Hacer cambios después
Edita un archivo en GitHub (ícono de lápiz) y guarda con **Commit changes**. Vercel publica la nueva versión sola en unos segundos.

## Moderar juegos

1. Entra a Supabase > tu proyecto > **Table Editor** > tabla `juegos`.
2. Busca los que tienen `estado` = `pendiente` (botón **Filter**: `estado` equals `pendiente`).
3. Cambia el estado a `aprobado` para publicarlo, o a `rechazado` para descartarlo. Escríbelo en minúsculas y sin tilde.
4. Recarga la página: los aprobados aparecen al instante.

No hace falta corregir mayúsculas, tildes ni espacios: la base de datos lo hace sola al guardar
(por ejemplo, "peru" se guarda como "Perú" y "topografia" como "Topografía"). Si ves materiales
juntos en una sola fila ("papel y lápiz"), sepáralos en filas distintas.

## Cambios frecuentes

- **Cambiar colores:** `css/estilos.css`, sección 1.
- **Cambiar textos de la cabecera o el pie:** `index.html`.
- **Agregar una rama:** en tres lugares: `supabase/esquema.sql` (la lista de la columna `ramas`), `js/app.js` (la lista `RAMAS`) e `index.html` (el filtro y las casillas del formulario). La base de datos también debe actualizarse.
- **Agregar un país a la lista:** en dos lugares: el menú "País" de `index.html` y la función `normalizar_pais` en Supabase (ver `supabase/esquema.sql`, sección 3). Lo mismo para las instrucciones sugeridas (`normalizar_instruccion` y la lista `instrucciones` de `index.html`).
- **Cantidad de scouts:** dos números, `cantidad_min` (obligatorio, 1 a 300) y `cantidad_max` (opcional; vacío = sin máximo). En la página se muestra como "De 10 a 20 scouts", "Desde 5 scouts" o "Cualquier cantidad".
- **Cómo se guardan los materiales:** como una lista `[{"material": "Conos", "cantidad": "4"}]`. Una lista vacía significa que el juego no necesita materiales.
- **Agregar un campo al formulario:** primero una columna nueva en Supabase, luego el campo en `index.html` y por último el dato en el objeto `juego` dentro de `js/app.js` (sección 9).

## Seguridad

- La publishable key de `js/config.js` puede estar a la vista: está hecha para páginas públicas.
- **Nunca** pongas la secret key (o `service_role`) en ningún archivo del proyecto.
- La página no pide ni muestra datos de menores. El formulario exige confirmarlo antes de enviar.
