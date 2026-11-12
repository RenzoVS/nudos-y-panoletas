// =====================================================================
// NUDOS Y PAÑOLETAS · Lógica de la página
// =====================================================================
// Índice:
//   1. Listas de opciones
//   2. Conexión con Supabase
//   3. Estado de la página
//   4. Utilidades (funciones de ayuda)
//   5. Cargar juegos desde la base de datos
//   6. Filtros y búsqueda
//   7. Dibujar la lista de juegos
//   8. Ver un juego (ventana de detalle)
//   9. Publicar un juego (formulario)
//  10. Arranque
// =====================================================================


// ---------------------------------------------------------------------
// 1. LISTAS DE OPCIONES
// Traducen los valores guardados en la base de datos ("lobatos") a
// textos para mostrar ("Lobatos"). Si agregas una rama, agrégala aquí,
// en index.html (filtro y formulario) y en supabase/esquema.sql.
// ---------------------------------------------------------------------
const RAMAS = {
  lobatos: "Lobatos",
  scouts: "Scouts",
  caminantes: "Caminantes",
  rovers: "Rovers",
  todas: "Todas las ramas",
};

const RIESGOS = { bajo: "Riesgo bajo", medio: "Riesgo medio", alto: "Riesgo alto" };
const TIPOS = { activo: "Activo", pasivo: "Pasivo" };


// ---------------------------------------------------------------------
// 2. CONEXIÓN CON SUPABASE
// Los datos de conexión vienen de js/config.js. Si todavía no se
// llenaron, la página muestra un aviso en vez de fallar.
// ---------------------------------------------------------------------
const estaConfigurado =
  window.CONFIG &&
  CONFIG.SUPABASE_URL.startsWith("https://") &&
  !CONFIG.SUPABASE_KEY.startsWith("PEGA_");

// "db" es el cliente con el que hablamos con la base de datos.
const db = estaConfigurado
  ? window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY)
  : null;


// ---------------------------------------------------------------------
// 3. ESTADO DE LA PÁGINA
// Un solo lugar donde guardamos lo que la página "sabe" en cada momento.
// Cuando algo cambia, llamamos a dibujarLista() para actualizar la vista.
// ---------------------------------------------------------------------
const estado = {
  juegos: [],          // todos los juegos aprobados que llegaron de Supabase
  cargando: true,      // true mientras esperamos la respuesta
  error: null,         // texto del error si algo falló
  filtros: {
    texto: "",
    rama: "",
    riesgo: "",
    tipo: "",
    soloAplicativos: false,
  },
};


// ---------------------------------------------------------------------
// 4. UTILIDADES
// ---------------------------------------------------------------------

// Atajo para buscar un elemento del HTML: $("#lista") en vez de
// document.querySelector("#lista").
const $ = (selector) => document.querySelector(selector);

// Crea un elemento HTML con clase y texto.
// Usamos textContent (y no innerHTML) a propósito: así, si alguien
// escribe código en un formulario, se muestra como texto y no se ejecuta.
function crear(etiqueta, clase, texto) {
  const el = document.createElement(etiqueta);
  if (clase) el.className = clase;
  if (texto !== undefined && texto !== null) el.textContent = texto;
  return el;
}

// Pasa a minúsculas y quita tildes, para que "orientacion"
// encuentre "Orientación" en la búsqueda.
function normalizar(texto) {
  return (texto || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

// Muestra un aviso pequeño abajo de la pantalla durante 2,5 segundos.
function avisar(mensaje) {
  const aviso = $("#aviso-flotante");
  aviso.textContent = mensaje;
  aviso.classList.add("visible");
  clearTimeout(avisar.temporizador);
  avisar.temporizador = setTimeout(() => aviso.classList.remove("visible"), 2500);
}

// Crea el "parche" de color que indica el nivel de riesgo.
function crearParche(riesgo) {
  return crear("span", `parche parche--${riesgo}`, RIESGOS[riesgo]);
}

// Crea las etiquetas pequeñas (tipo, cantidad, aplicativo).
function crearEtiquetas(juego) {
  const contenedor = crear("div", "etiquetas");
  contenedor.append(
    crear("span", `etiqueta etiqueta--${juego.tipo}`, TIPOS[juego.tipo]),
    // Si ya escribieron "scouts" en la cantidad, no lo repetimos.
    crear("span", "etiqueta", normalizar(juego.cantidad).includes("scout") ? juego.cantidad : `${juego.cantidad} scouts`)
  );
  if (juego.aplicativo) {
    contenedor.append(crear("span", "etiqueta", `Aplicativo: ${juego.tipo_instruccion}`));
  }
  return contenedor;
}


// ---------------------------------------------------------------------
// 5. CARGAR JUEGOS DESDE LA BASE DE DATOS
// Pide a Supabase los juegos aprobados, del más nuevo al más antiguo.
// Aunque no pongamos el filtro de "aprobado", la regla de seguridad de
// la base de datos ya impide ver los pendientes; lo ponemos igual para
// que el código sea claro.
// ---------------------------------------------------------------------
async function cargarJuegos() {
  if (!db) {
    estado.cargando = false;
    estado.error = "sin-configurar";
    dibujarLista();
    return;
  }

  const { data, error } = await db
    .from("juegos")
    .select("id, creado_en, titulo, descripcion, materiales, rama, riesgo, tipo, cantidad, aplicativo, tipo_instruccion, autor, grupo_scout, pais")
    .eq("estado", "aprobado")
    .order("creado_en", { ascending: false })
    .limit(500); // límite de seguridad; cuando haya más juegos, se puede paginar

  estado.cargando = false;

  if (error) {
    console.error("Error al cargar juegos:", error); // detalle técnico en la consola del navegador (F12)
    estado.error = "carga";
  } else {
    estado.juegos = data;
  }

  dibujarLista();
  abrirJuegoDelEnlace(); // si llegaron con un enlace directo a un juego, lo abrimos
}


// ---------------------------------------------------------------------
// 6. FILTROS Y BÚSQUEDA
// Se filtra en el navegador (no en la base de datos) porque al inicio
// habrá pocos juegos y así la búsqueda es instantánea.
// ---------------------------------------------------------------------
function juegosFiltrados() {
  const f = estado.filtros;
  const busqueda = normalizar(f.texto);

  return estado.juegos.filter((juego) => {
    // Un juego "para todas las ramas" aparece al filtrar cualquier rama.
    if (f.rama && juego.rama !== f.rama && juego.rama !== "todas") return false;
    if (f.riesgo && juego.riesgo !== f.riesgo) return false;
    if (f.tipo && juego.tipo !== f.tipo) return false;
    if (f.soloAplicativos && !juego.aplicativo) return false;

    if (busqueda) {
      // Buscamos en el título, la descripción, los materiales y la instrucción.
      const textoDelJuego = normalizar(
        [juego.titulo, juego.descripcion, juego.materiales, juego.tipo_instruccion].join(" ")
      );
      if (!textoDelJuego.includes(busqueda)) return false;
    }
    return true;
  });
}

// Conecta cada control del buscador con su filtro.
function prepararFiltros() {
  $("#busqueda").addEventListener("input", (e) => {
    estado.filtros.texto = e.target.value;
    dibujarLista();
  });
  $("#filtro-rama").addEventListener("change", (e) => {
    estado.filtros.rama = e.target.value;
    dibujarLista();
  });
  $("#filtro-riesgo").addEventListener("change", (e) => {
    estado.filtros.riesgo = e.target.value;
    dibujarLista();
  });
  $("#filtro-tipo").addEventListener("change", (e) => {
    estado.filtros.tipo = e.target.value;
    dibujarLista();
  });
  $("#filtro-aplicativo").addEventListener("change", (e) => {
    estado.filtros.soloAplicativos = e.target.checked;
    dibujarLista();
  });
}

// Vuelve todos los filtros a su valor inicial.
function limpiarFiltros() {
  estado.filtros = { texto: "", rama: "", riesgo: "", tipo: "", soloAplicativos: false };
  $("#busqueda").value = "";
  $("#filtro-rama").value = "";
  $("#filtro-riesgo").value = "";
  $("#filtro-tipo").value = "";
  $("#filtro-aplicativo").checked = false;
  dibujarLista();
}


// ---------------------------------------------------------------------
// 7. DIBUJAR LA LISTA DE JUEGOS
// Borra la lista y la vuelve a crear con los juegos que pasan los filtros.
// ---------------------------------------------------------------------

// Mensaje en lugar de la lista (cargando, vacío, error).
function crearMensaje(titulo, texto, textoBoton, alHacerClic) {
  const caja = crear("div", "mensaje");
  caja.append(crear("h2", null, titulo), crear("p", null, texto));
  if (textoBoton) {
    const boton = crear("button", "boton boton--principal", textoBoton);
    boton.type = "button";
    boton.addEventListener("click", alHacerClic);
    caja.append(boton);
  }
  return caja;
}

// Crea la ficha de un juego. Es un botón: al hacer clic abre el detalle.
function crearFicha(juego) {
  const ficha = crear("button", "ficha");
  ficha.type = "button";

  const cabeza = crear("div", "ficha__cabeza");
  cabeza.append(crear("span", "ficha__rama", RAMAS[juego.rama]), crearParche(juego.riesgo));

  ficha.append(
    cabeza,
    crear("h2", "ficha__titulo", juego.titulo),
    crear("p", "ficha__descripcion", juego.descripcion),
    crearEtiquetas(juego)
  );

  ficha.addEventListener("click", () => abrirDetalle(juego));
  return ficha;
}

function dibujarLista() {
  const lista = $("#lista");
  const resumen = $("#resumen");
  lista.replaceChildren(); // vacía la lista

  if (estado.cargando) {
    resumen.textContent = "";
    lista.append(crearMensaje("Cargando juegos…", "Un momento, estamos trayendo los juegos."));
    return;
  }

  if (estado.error === "sin-configurar") {
    resumen.textContent = "";
    lista.append(crearMensaje(
      "Falta conectar la base de datos",
      "Completa la URL y la publishable key de Supabase en el archivo js/config.js."
    ));
    return;
  }

  if (estado.error === "carga") {
    resumen.textContent = "";
    lista.append(crearMensaje(
      "No se pudieron cargar los juegos",
      "Revisa tu conexión a internet e inténtalo de nuevo.",
      "Reintentar",
      () => { estado.cargando = true; estado.error = null; dibujarLista(); cargarJuegos(); }
    ));
    return;
  }

  if (estado.juegos.length === 0) {
    resumen.textContent = "";
    lista.append(crearMensaje(
      "Todavía no hay juegos publicados",
      "Comparte el primero: un juego que haya funcionado en tus reuniones.",
      "Publicar un juego",
      abrirFormulario
    ));
    return;
  }

  const visibles = juegosFiltrados();
  const total = estado.juegos.length;
  resumen.textContent =
    visibles.length === total
      ? `${total} ${total === 1 ? "juego" : "juegos"}`
      : `${visibles.length} de ${total} juegos`;

  if (visibles.length === 0) {
    lista.append(crearMensaje(
      "Ningún juego coincide con tu búsqueda",
      "Prueba con otra palabra o quita algún filtro.",
      "Quitar filtros",
      limpiarFiltros
    ));
    return;
  }

  visibles.forEach((juego) => lista.append(crearFicha(juego)));
}


// ---------------------------------------------------------------------
// 8. VER UN JUEGO (VENTANA DE DETALLE)
// Cada juego tiene su propio enlace: la dirección termina en
// #juego-<id>. Así se puede compartir un juego por WhatsApp o Instagram.
// ---------------------------------------------------------------------
function abrirDetalle(juego) {
  const detalle = $("#detalle");
  detalle.replaceChildren();

  const titulo = crear("h2", "ventana__titulo", juego.titulo);
  titulo.id = "detalle-titulo";

  const datos = crear("div", "detalle__datos");
  datos.append(
    crear("span", "etiqueta", RAMAS[juego.rama]),
    crearParche(juego.riesgo),
    ...crearEtiquetas(juego).children
  );

  // Bloque con subtítulo y texto, por ejemplo "Materiales".
  const bloque = (subtitulo, texto) => {
    const b = crear("div", "detalle__bloque");
    b.append(crear("h3", null, subtitulo), crear("p", null, texto));
    return b;
  };

  // "Compartido por Halcón Sereno · Grupo 52 · Perú" (solo lo que hayan llenado)
  const partesAutor = [juego.autor, juego.grupo_scout, juego.pais].filter(Boolean);
  const autor = crear(
    "p",
    "detalle__autor",
    partesAutor.length ? `Compartido por ${partesAutor.join(", ")}` : "Compartido por un dirigente"
  );

  const acciones = crear("div", "ventana__acciones");
  const botonCopiar = crear("button", "boton boton--secundario", "Copiar enlace");
  botonCopiar.type = "button";
  botonCopiar.addEventListener("click", copiarEnlace);
  acciones.append(botonCopiar);

  detalle.append(
    titulo,
    datos,
    bloque("En qué consiste", juego.descripcion),
    bloque("Materiales", juego.materiales),
    autor,
    acciones
  );

  // Ponemos el enlace del juego en la barra de direcciones sin recargar la página.
  history.replaceState(null, "", `#juego-${juego.id}`);
  $("#ventana-juego").showModal();
}

async function copiarEnlace() {
  try {
    await navigator.clipboard.writeText(location.href);
    avisar("Enlace copiado");
  } catch {
    avisar("No se pudo copiar. Copia la dirección del navegador.");
  }
}

// Si la página se abrió con un enlace #juego-<id>, abrimos ese juego.
function abrirJuegoDelEnlace() {
  if (!location.hash.startsWith("#juego-")) return;
  const id = location.hash.replace("#juego-", "");
  const juego = estado.juegos.find((j) => j.id === id);
  if (juego) abrirDetalle(juego);
}


// ---------------------------------------------------------------------
// 9. PUBLICAR UN JUEGO (FORMULARIO)
// ---------------------------------------------------------------------
const formulario = $("#formulario");
const ventanaPublicar = $("#ventana-publicar");

function abrirFormulario() {
  if (!db) {
    avisar("La página aún no está conectada a la base de datos.");
    return;
  }
  ventanaPublicar.showModal();
}

// Mostrar u ocultar el campo de instrucción según la casilla "aplicativo".
$("#f-aplicativo").addEventListener("change", (e) => {
  $("#campo-instruccion").hidden = !e.target.checked;
});

// Marca en rojo los campos incompletos y devuelve true si todo está bien.
function validarFormulario() {
  let valido = true;
  formulario.querySelectorAll(".invalido").forEach((el) => el.classList.remove("invalido"));

  // Campos de texto y listas obligatorios (los que tienen "required" en el HTML)
  formulario.querySelectorAll("input[type=text][required], textarea[required], select[required]").forEach((campo) => {
    if (!campo.checkValidity()) {
      campo.classList.add("invalido");
      valido = false;
    }
  });

  // Grupos de opciones (riesgo y tipo): debe haber una marcada
  formulario.querySelectorAll(".opciones").forEach((grupo) => {
    if (!grupo.querySelector("input:checked")) {
      grupo.classList.add("invalido");
      valido = false;
    }
  });

  // Si es aplicativo, la instrucción es obligatoria
  const instruccion = $("#f-instruccion");
  if ($("#f-aplicativo").checked && !instruccion.value.trim()) {
    instruccion.classList.add("invalido");
    valido = false;
  }

  return valido;
}

function mostrarErrorFormulario(mensaje) {
  const caja = $("#error-formulario");
  caja.textContent = mensaje;
  caja.hidden = !mensaje;
}

formulario.addEventListener("submit", async (evento) => {
  evento.preventDefault(); // evita que el navegador recargue la página
  mostrarErrorFormulario("");

  if (!validarFormulario()) {
    mostrarErrorFormulario("Completa los campos marcados en rojo.");
    return;
  }
  if (!$("#f-cuidado").checked) {
    mostrarErrorFormulario("Confirma que el juego no incluye datos ni fotos de menores.");
    return;
  }

  const datos = new FormData(formulario);

  // Si el campo trampa viene lleno, es un robot: fingimos éxito y no guardamos.
  if (datos.get("sitio_web")) {
    mostrarGracias();
    return;
  }

  // Convierte un texto vacío en null (así la base de datos lo guarda vacío).
  const textoOpcional = (nombre) => (datos.get(nombre) || "").trim() || null;
  const esAplicativo = datos.get("aplicativo") === "on";

  // El objeto que se guarda. Cada nombre es una columna de la tabla "juegos".
  // No enviamos "estado": la base de datos lo pone en "pendiente".
  const juego = {
    titulo: datos.get("titulo").trim(),
    descripcion: datos.get("descripcion").trim(),
    materiales: datos.get("materiales").trim(),
    rama: datos.get("rama"),
    riesgo: datos.get("riesgo"),
    tipo: datos.get("tipo"),
    cantidad: datos.get("cantidad").trim(),
    aplicativo: esAplicativo,
    tipo_instruccion: esAplicativo ? textoOpcional("tipo_instruccion") : null,
    autor: textoOpcional("autor"),
    grupo_scout: textoOpcional("grupo_scout"),
    pais: textoOpcional("pais"),
  };

  const botonEnviar = $("#btn-enviar");
  botonEnviar.disabled = true;
  botonEnviar.textContent = "Enviando…";

  // Guardamos en Supabase. No pedimos que devuelva la fila (sin .select())
  // porque los visitantes no pueden leer juegos pendientes.
  const { error } = await db.from("juegos").insert(juego);

  botonEnviar.disabled = false;
  botonEnviar.textContent = "Enviar juego";

  if (error) {
    console.error("Error al enviar juego:", error);
    mostrarErrorFormulario("No se pudo enviar el juego. Revisa tu conexión e inténtalo de nuevo.");
    return;
  }

  mostrarGracias();
});

// Reemplaza el formulario por un mensaje de agradecimiento.
function mostrarGracias() {
  formulario.hidden = true;

  const gracias = crear("div", "gracias");
  gracias.id = "gracias";
  const titulo = crear("h2", "ventana__titulo", "¡Gracias por compartir tu juego!");
  titulo.style.marginRight = "0";
  const boton = crear("button", "boton boton--principal", "Volver a los juegos");
  boton.type = "button";
  boton.addEventListener("click", () => ventanaPublicar.close());

  gracias.append(
    titulo,
    crear("p", null, "Lo revisaremos y aparecerá en la página cuando esté aprobado."),
    boton
  );
  ventanaPublicar.append(gracias);
}

// Al cerrar la ventana, dejamos el formulario limpio para la próxima vez.
ventanaPublicar.addEventListener("close", () => {
  const gracias = $("#gracias");
  if (gracias) {
    gracias.remove();
    formulario.reset();
    $("#campo-instruccion").hidden = true;
  }
  formulario.hidden = false;
  mostrarErrorFormulario("");
  formulario.querySelectorAll(".invalido").forEach((el) => el.classList.remove("invalido"));
});


// ---------------------------------------------------------------------
// 10. ARRANQUE
// Lo que pasa cuando la página termina de cargar.
// ---------------------------------------------------------------------

// Botones con "data-cerrar" cierran la ventana en la que están.
document.querySelectorAll("[data-cerrar]").forEach((boton) => {
  boton.addEventListener("click", () => boton.closest("dialog").close());
});

// Hacer clic en el fondo oscuro (fuera del recuadro) también cierra la ventana.
// Comparamos la posición del clic con los bordes de la ventana, porque un
// clic en el margen interno de la ventana también cuenta como clic en ella.
document.querySelectorAll("dialog").forEach((ventana) => {
  ventana.addEventListener("click", (e) => {
    if (e.target !== ventana) return;
    const r = ventana.getBoundingClientRect();
    const fuera = e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
    if (fuera) ventana.close();
  });
});

// Al cerrar el detalle, quitamos el #juego-... de la dirección.
$("#ventana-juego").addEventListener("close", () => {
  history.replaceState(null, "", location.pathname + location.search);
});

$("#btn-publicar").addEventListener("click", abrirFormulario);

prepararFiltros();
dibujarLista();  // muestra "Cargando…"
cargarJuegos();  // trae los juegos y vuelve a dibujar
