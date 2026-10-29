#!/usr/bin/env python3
"""Pruebas del intérprete de frases del menú (tools/intent.py).

    python3 tools/test_intent.py

Las frases imitan cómo escriben de verdad las personas con poca experiencia en tecnología:
mensajes en pedacitos, errores de tipeo, voseo, abreviaturas, mayúsculas, apuro o
preocupación, y referencias vagas ("eso", "la plataforma", "lo de ayer"). Están reescritas a
partir de conversaciones reales con clientes, sin nombres ni datos de nadie.
Correrlas antes de cada push si se toca intent.py.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from intent import classify  # noqa: E402

MCP = "instagram facebook youtube chatwoot meta-ads google-ads brave-search ssh-infra easypanel " \
      "elevenlabs kling renoise obsidian inkscape gimp obs video-audio codebase-memory".split()
PACKS = "marketing diseno codigo".split()

CASOS = [
    # Saludos y mensajes en pedacitos: se abre la charla, no se intenta adivinar
    ("Juan", "hablar"),  # el nombre de quien atiende, solo: es un "che, ¿estás?"
    ("buen dia", "hablar"),
    ("Hola, como estas?", "hablar"),
    ("te consulto", "hablar"),
    ("holaaa buenas", "hablar"),
    # Charla: se contesta amable, nunca "no te entendí"
    ("gracias!!", "charla"),
    ("perdon", "charla"),
    ("jajaja", "charla"),
    ("UUUFFF QUE ALIVIO", "charla"),
    ("dale genial", "charla"),
    # Cierres
    ("LISTO!!! YA ESTA OLVIDATE", "salir"),
    ("listo gracias", "salir"),
    ("chau", "salir"),
    # Pedidos vagos o de trabajo: van a Claude, que pregunta lo que falte
    ("Podes revisar porfa?", "tarea"),
    ("encontre este mail de la base de datos, que hago?", "tarea"),
    ("me acorde que te mande un archivo por la plataforma", "tarea"),
    ("haceme un post para instagram de la promo de brasil", "tarea"),
    ("publica en el face lo del viaje a buzios", "tarea"),
    ("respondele al cliente que pregunto por el paquete", "tarea"),
    ("necesito un presupuesto para un grupo de 4 a bariloche", "tarea"),
    ("cuanto vendimos este mes?", "tarea"),
    ("revisa el contrato que te pase", "tarea"),
    ("actualiza los precios de la web", "tarea"),
    ("agendame una reunion con el contador el martes", "tarea"),
    ("armame un video corto para las redes", "tarea"),
    ("recordame el alias para transferir", "tarea"),
    ("mandale un mail a todos los clientes de octubre", "tarea"),
    ("no me anda la pagina web del negocio", "tarea"),
    ("me cague en las patas, no sabia que era asi", "tarea"),
    # Algo del sistema no anda
    ("no me anda instagram", "revisar:deep"),
    ("el chatwoot no conecta", "revisar:deep"),
    ("se colgo claude", "revisar"),
    ("ideas box no funciona", "revisar"),
    ("revisa que este todo bien", "revisar"),
    ("chequea si anda todo", "revisar"),
    # Conectar herramientas
    ("conectar chatwoot", "mcp-add:chatwoot"),
    ("conetá mi insta", "mcp-add:instagram"),
    ("quiero vincular el face", "mcp-add:facebook"),
    ("te paso la clave de google ads", "mcp-add:google-ads"),
    ("conectar una herramienta", "mcp-add"),
    ("quiero conectar una herramienta que no esta en la lista", "mcp-new"),
    # Habilidades
    ("sumar habilidades de marketing", "skills-add:marketing"),
    ("que habilidades hay?", "skills-add"),
    ("quiero enseñarles como trabajo yo los presupuestos", "skills-new"),
    ("crear una abilidad nueva", "skills-new"),
    # Plan de Claude y motor local
    ("se me acabo claude", "motor"),
    ("me quede sin creditos", "motor"),
    ("cuanto me queda del plan?", "motor"),
    ("instala el motor local", "motor-install"),
    ("quiero poder trabajar sin internet en mi compu", "motor-install"),
    ("segui con lo que quedo cortado", "continuar"),
    ("retoma donde quedamos", "continuar"),
    # Otros modelos
    ("conectar chatgpt", "motor-conectar:openai"),
    ("te paso la clave de openai", "motor-conectar:openai"),
    ("quiero conectar gemini", "motor-conectar:gemini"),
    ("usemos chatgpt para esto", "con:openai"),
    ("quiero trabajar con gemini", "con:gemini"),
    # Resto del menú
    ("hace un respaldo", "respaldo"),
    ("hacé una copia de seguridad de todo", "respaldo"),
    ("actualizar", "actualizar"),
    ("actualiza ideas box", "actualizar"),
    ("donde estan los archivos que genero?", "carpeta"),
    ("abrir el panel", "panel"),
    ("programa una tarea para todos los lunes", "panel"),
    ("llevar mi empresa en un pendrive", "paquete"),
    ("no me aparece el icono en el escritorio", "icono"),
    ("instalar de nuevo ideas box", "instalar"),
    ("ayuda", "ayuda"),
    ("no se que hacer", "ayuda"),
    ("que puedo hacer con esto?", "ayuda"),
    ("hablar con mis agentes", "hablar"),
]


def main():
    fallas = 0
    for frase, esperado in CASOS:
        obtenido = classify(frase, MCP, PACKS)
        if obtenido != esperado:
            fallas += 1
            print(f"✗ {frase!r}: esperaba {esperado}, salió {obtenido}")
    total = len(CASOS)
    print(f"{'✓' if not fallas else '✗'} {total - fallas}/{total} frases bien interpretadas")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
