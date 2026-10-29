#!/usr/bin/env python3
"""Interpreta lo que escribe una persona en el menú de Ideas Box, con sus palabras.

Uso: intent.py --mcp "id1 id2 …" --packs "id1 id2 …" -- <frase>
Imprime una acción para lib/menu.sh:
  tarea                 pedido de trabajo → se le pasa la frase a Claude tal cual
  hablar | ayuda | salir | charla (gracias, perdón, jaja: se contesta amable) | nada
  revisar | revisar:deep (un conector puntual que no anda)
  mcp-add[:id] | mcp-new | skills-add[:pack] | skills-new
  motor | motor-install | continuar | motor-conectar:<openai|gemini> | con:<openai|gemini>
  paquete | icono | panel | respaldo | actualizar | carpeta | instalar

Criterio: la mayoría de lo que escribe alguien que no es técnico es TRABAJO ("haceme un post",
"respondele a Juan"), no administración del sistema. Una frase solo va a una opción del menú
cuando habla del sistema en sí (conectar, sumar, respaldar, actualizar Ideas Box…); todo lo
demás va a Claude, que la interpreta con los agentes. Mejor eso que un «no te entendí».
"""
import difflib
import re
import sys
import unicodedata

# Abreviaturas y errores frecuentes, palabra por palabra
TYPOS = {
    "q": "que", "xq": "porque", "pq": "porque", "x": "por", "tmb": "tambien", "tb": "tambien",
    "porfa": "", "porfavor": "", "xfa": "", "pls": "", "plis": "",
    "insta": "instagram", "ig": "instagram", "face": "facebook", "fb": "facebook",
    "wsp": "whatsapp", "wpp": "whatsapp", "wasap": "whatsapp", "guasap": "whatsapp", "watsap": "whatsapp",
    "yt": "youtube", "youtub": "youtube", "mail": "correo", "email": "correo", "e-mail": "correo",
    "bkp": "backup", "back": "backup", "compu": "computadora", "pc": "computadora",
    "abilidad": "habilidad", "abilidades": "habilidades", "skils": "skills", "skil": "skill",
    "conetar": "conectar", "coneccion": "conexion", "concectar": "conectar",
    "respado": "respaldo", "resplado": "respaldo", "actualisar": "actualizar", "atualizar": "actualizar",
    "chatgpt": "chatgpt", "chat-gpt": "chatgpt", "chatgtp": "chatgpt", "gpt": "chatgpt", "openia": "openai",
    "geminis": "gemini", "bard": "gemini",
    "instalr": "instalar", "intalar": "instalar", "credito": "creditos",
}

# Vocabulario contra el que se corrigen palabras mal escritas (solo palabras de 5+ letras)
VOCAB = """conectar conecta conectame conectes conector conectores conexion vincular integrar integracion
herramienta herramientas aplicacion habilidad habilidades skills respaldo respaldar backup actualizar
actualiza revisar revisa diagnostico funciona funcionando pendrive portable panel tablero carpeta
archivos instalar instalacion reinstalar limite limites creditos tokens claude ollama motor continuar
retomar seguir ayuda instagram facebook whatsapp youtube chatwoot easypanel inkscape obsidian
elevenlabs renoise google servidor servidores programar automatico enseñar ensenar aprender empresa
agentes agente copia seguridad version chatgpt openai gemini""".split()

STOP = set("""el la los las un una unos unas de del al a en y o que me te se mi mis tu tus su sus lo
por para con sin es esta este esto eso ese hay quiero queria quisiera necesito podes podrias puedes
vos yo nos le les ahora ya favor hola buenas buen dia dias tardes noches gracias che bueno dale""".split())

ADMIN_VERB = r"(conect|vincul|enlaz|integr|sum[aá]|agreg|anad|instal|configur|activ|dar acceso|acceso a|" \
             r"credencial|token|clave|contrasen|login|inicia\w* sesion|cuenta de|logue)"
SYSTEM_OBJ = r"(ideas ?box|ideasbox|conector|herramienta|agente|claude|panel|menu|instalacion|habilidad|" \
             r"skill|motor|sistema|ollama|integracion)"

# Formas comunes de nombrar a cada conector, además de su id
ALIASES = {
    "instagram": ["instagram"], "facebook": ["facebook"], "youtube": ["youtube"],
    "chatwoot": ["chatwoot", "bandeja de atencion", "bandeja de mensajes"],
    "meta-ads": ["meta ads", "anuncios de meta", "publicidad de meta", "anuncios de facebook"],
    "facebook-ads": ["facebook ads"],
    "google-ads": ["google ads", "adwords", "anuncios de google", "publicidad de google"],
    "brave-search": ["brave", "buscador"], "ssh-infra": ["ssh", "servidor", "servidores"],
    "easypanel": ["easypanel"], "codebase-memory": ["codebase", "grafo de codigo"],
    "video-audio": ["ffmpeg"], "elevenlabs": ["elevenlabs", "eleven labs"],
    "kling": ["kling"], "renoise": ["renoise"], "obsidian": ["obsidian"],
    "inkscape": ["inkscape"], "gimp": ["gimp"], "obs": ["obs studio"], "ponytail": ["ponytail"],
}


def normalize(text):
    t = unicodedata.normalize("NFD", text.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = re.sub(r"([a-z])\1{2,}", r"\1", t)          # "holaaa" → "hola"
    t = re.sub(r"[^a-z0-9ñ\- ]+", " ", t)
    words = []
    for w in t.split():
        w = TYPOS.get(w, w)
        if len(w) >= 5 and w not in VOCAB:
            close = difflib.get_close_matches(w, VOCAB, n=1, cutoff=0.86)
            if close:
                w = close[0]
        if w:
            words.append(w)
    return " ".join(words)


def has(t, pattern):
    return re.search(pattern, t) is not None


def tool_named(t, mcp_ids):
    padded = f" {t} "
    for mid in mcp_ids:
        names = ALIASES.get(mid, []) + [mid, mid.replace("-", " ")]
        short = mid.split("-")[0]
        if len(short) >= 4:
            names.append(short)
        for n in names:
            if f" {n} " in padded:
                return mid
    return None


def classify(phrase, mcp_ids=(), pack_ids=()):
    t = normalize(phrase)
    if not t:
        return "nada"
    content = [w for w in t.split() if w not in STOP]
    tool = tool_named(t, mcp_ids)

    # Escriben en pedacitos: un saludo solo, un "gracias" o un "listo" no son pedidos
    if has(t, r"^(listo|ya esta|olvidate|nada|salir|chau|adios|exit|terminar|cerrar|me voy|hasta luego|nos vemos)"
              r"( (listo|ya esta|olvidate|nada|gracias|chau|todo bien|resuelto|solucionado))*$"):
        return "salir"
    if has(t, r"^((gracias|muchas gracias|genial|perfecto|joya|barbaro|buenisimo|perdon|disculpa|ok|oka|dale|"
              r"jaja|jajaja|ja|jeje|uf|uff|bien|todo bien|alivio|que alivio|casi me muero) ?)+$"):
        return "charla"
    if has(t, r"^((hola|buenas|buen dia|buenos dias|buenas tardes|buenas noches|che|como estas|como va|"
              r"que tal|te consulto|una consulta|consulta|una pregunta|estas|ahi|hey|holis) ?)+$"):
        return "hablar"
    if has(t, r"^(ayuda|help|\?)$|no se (que|como|por donde)|que (puedo|podes|puedes|sabes|se puede) hacer|"
              r"como (funciona|se usa|uso|empiezo)|que (es|hace) (esto|ideas ?box)|que opciones"):
        return "ayuda"

    # --- otros modelos: OpenAI (ChatGPT) y Gemini ------------------------------------
    prov = "openai" if has(t, r"\b(chatgpt|openai)\b") else "gemini" if has(t, r"\b(gemini|ia de google)\b") else None
    if prov:
        if has(t, ADMIN_VERB + r"|clave|api ?key|cuenta"):
            return f"motor-conectar:{prov}"
        if has(t, r"(usa|usar|usemos|trabaj|con |abri|abrir|pasa|cambia|probar|proba)"):
            return f"con:{prov}"

    # --- plan de Claude y motor local -------------------------------------------------
    local = r"(motor local|modelo local|ia local|ollama|respaldo local|sin internet|offline|en mi (compu|computadora|equipo))"
    if has(t, local) and has(t, r"(instal|activ|pone|configur|baj|quiero|necesito tener|agreg|sum)"):
        return "motor-install"
    if has(t, r"(segui|continu|retom)\w*") and has(t, r"(local|donde (quedo|quedamos|estaba)|lo que (estaba|quedo|venia)|"
                                                   r"se corto|cortado|sin claude|trabajo pendiente)"):
        return "continuar"
    if has(t, r"(limite|creditos|tokens|se (me )?(acabo|termino|agoto|corto)|me quede sin|sin (plan|claude|creditos)|"
              r"cuanto (me )?queda|uso de claude|consumo|plan de claude|plan pro|" + local[1:-1] + ")"):
        return "motor"

    # --- algo del sistema no anda ----------------------------------------------------
    problema = r"(no (me |te |nos |le )?(anda|funciona|responde|conecta|abre|arranca|carga|me deja|aparece|sale|puedo (entrar|abrir|ver|usar))|" \
               r"se (rompio|colgo|trabo|cayo|tildo|cerro|borro)|desaparec|falla|fallando|anda mal|esta roto|error)"
    if has(t, problema) and (tool or has(t, SYSTEM_OBJ)):
        return "revisar:deep" if tool else "revisar"

    # --- conectores ------------------------------------------------------------------
    crear = has(t, r"(crea|crear|nuev|armar|arma |propi|no esta|no aparece|otra|que no (esta|hay)|falta)")
    if tool and has(t, ADMIN_VERB):
        return f"mcp-add:{tool}"
    if has(t, r"(conector|herramienta|integracion|aplicacion|mcp|app )") and has(t, ADMIN_VERB + r"|(crea|nuev|sum|agreg|ver|que hay|lista)"):
        return "mcp-new" if crear else "mcp-add"
    if has(t, r"^(conectar|conecta|vincular|integrar)\b"):
        return "mcp-add"

    # --- habilidades -----------------------------------------------------------------
    if has(t, r"(habilidad|skill|pack|conocimiento)") or has(t, r"(ensena|ensenar|ensenales|que aprendan|aprender a)"):
        if crear or has(t, r"(ensena|que aprendan|aprender a|mi forma|como trabajo)"):
            return "skills-new"
        for pid in pack_ids:
            if f" {pid} " in f" {t} " or f" {pid.split('-')[0]} " in f" {t} ":
                return f"skills-add:{pid}"
        return "skills-add"

    # --- resto de las opciones del menú, solo si hablan del sistema -----------------
    if has(t, r"(pendrive|usb|portable|ideaspackage|disco externo|llevar (mi |la )?empresa)"):
        return "paquete"
    if has(t, r"(icono|acceso directo)") or (has(t, r"escritorio") and has(t, r"(crea|falta|no (esta|aparece)|volve)")):
        return "icono"
    if has(t, r"(panel|tablero)") or (has(t, r"program") and has(t, r"(tarea|automat|todos los|cada |diari|semanal|rutina)")):
        return "panel"
    if has(t, r"(respald|backup|resguard|copia de seguridad|guardar todo|guarda todo)"):
        return "respaldo"
    if has(t, r"(actualiz|update|ultima version|nueva version)") and (
            len(content) <= 2 or has(t, r"(ideas ?box|todo|sistema|version|habilidades|conectores|agentes)")):
        return "actualizar"
    if has(t, r"(abri|abrir|ver|mostra|donde (esta|estan|quedo|quedaron|guarda))") and has(
            t, r"(carpeta|archivos|lo que (genero|generaron|hicieron|hizo)|entregables|generad)"):
        return "carpeta"
    if has(t, r"(reinstal|rehacer|terminar de instalar|completar (la )?instalacion)") or (
            has(t, r"instal") and has(t, r"(ideas ?box|de nuevo|otra vez|todo)")) or t == "instalar":
        return "instalar"
    if t == "doctor" or (has(t, r"(revis|chequ|control|diagnost|verific|estado)") and
                         has(t, r"(todo|sistema|ideas ?box|instalacion|ande|anda|bien|conectores|agentes)")):
        return "revisar"
    if len(content) <= 2 and has(t, r"(hablar|agentes?|claude|chat|charlar|empezar|trabajar|abrir)"):
        return "hablar"

    # --- todo lo demás es un pedido de trabajo -----------------------------------------
    # Una palabra suelta que no es nada de lo anterior suele ser un nombre o un "che": se abre la charla
    return "tarea" if len(t.split()) >= 2 else "hablar"


def main(argv):
    mcp, packs, rest = [], [], []
    i = 0
    while i < len(argv):
        if argv[i] == "--mcp":
            mcp = argv[i + 1].split(); i += 2
        elif argv[i] == "--packs":
            packs = argv[i + 1].split(); i += 2
        elif argv[i] == "--":
            rest = argv[i + 1:]; break
        else:
            rest.append(argv[i]); i += 1
    print(classify(" ".join(rest), mcp, packs))


if __name__ == "__main__":
    main(sys.argv[1:])
