"""Original Bizigai planet specification. MIT. Metres; Godot +Y up/-Z forward."""
from __future__ import annotations
import math

WORLDS = {
    "lurga": {"name": "Lurga", "radius_m": 240.0, "seed": 5601,
        "biome": "Mesetas templadas de roca roja, praderas y arboledas de copa ancha",
        "habitable": True, "breathable_atmosphere": True, "gravity_m_s2": 9.0,
        "pois": [
            ("puerto_terracota", "Puerto Terracota", "landing"),
            ("huerto_cupulas", "Huerto de las Cúpulas", "greenhouse"),
            ("ojo_meseta", "Ojo de la Meseta", "observatory"),
            ("foro_rojo", "Foro Rojo", "ruins"),
            ("veta_ambar", "Veta Ámbar", "quarry"),
            ("paso_gemelo", "Paso Gemelo", "arches"),
            ("taller_nomada", "Taller Nómada", "workshop"),
            ("cisterna_juncos", "Cisterna de los Juncos", "water"),
            ("jardin_viento", "Jardín del Viento", "wind"),
            ("campo_helios", "Campo Helios", "solar"),
            ("anillo_testigos", "Anillo de los Testigos", "monolith"),
            ("casco_perdido", "Casco Perdido", "wreck"),
            ("refugio_brezos", "Refugio de los Brezos", "camp"),
            ("terrazas_semilla", "Terrazas Semilla", "farm"),
            ("pozo_calido", "Pozo Cálido", "thermal"),
            ("aguja_sur", "Aguja del Sur", "relay")],
    },
    "elur": {"name": "Elur", "radius_m": 200.0, "seed": 5602,
        "biome": "Altiplano alpino templado, tundra florida y lagunas geotérmicas",
        "habitable": True, "breathable_atmosphere": True, "gravity_m_s2": 8.0,
        "pois": [
            ("base_albor", "Base Albor", "landing"),
            ("vivero_aurora", "Vivero Aurora", "greenhouse"),
            ("mirador_cenit", "Mirador del Cénit", "observatory"),
            ("claustro_nieve", "Claustro de Nieve", "ruins"),
            ("jardin_cuarzo", "Jardín de Cuarzo", "quarry"),
            ("puerta_desfiladero", "Puerta del Desfiladero", "arches"),
            ("estacion_alpina", "Estación Alpina", "workshop"),
            ("laguna_espejo", "Laguna Espejo", "water"),
            ("crestas_brisa", "Crestas de la Brisa", "wind"),
            ("terraza_sol", "Terraza del Sol", "solar"),
            ("corona_ecos", "Corona de Ecos", "monolith"),
            ("quilla_boreal", "Quilla Boreal", "wreck"),
            ("campamento_lumen", "Campamento Lumen", "camp"),
            ("bancales_alpinos", "Bancales Alpinos", "farm"),
            ("termas_azules", "Termas Azules", "thermal"),
            ("faro_austral", "Faro Austral", "relay")],
    },
}


def normalize(v):
    length = math.sqrt(sum(x*x for x in v))
    if not math.isfinite(length) or length < 1e-9:
        raise ValueError("Direction must be finite and non-zero")
    return tuple(x / length for x in v)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def poi_direction(index):
    if not isinstance(index, int) or not 0 <= index < 16:
        raise ValueError("POI index outside [0, 15]")
    y = 1 - 2 * (index + .5) / 16
    angle = index * math.pi * (3 - math.sqrt(5)) + .35
    r = math.sqrt(1-y*y)
    return (r * math.sin(angle), y, -r * math.cos(angle))


def base_height(world, direction):
    if world not in WORLDS:
        raise ValueError("Unknown world")
    x, y, z = normalize(direction)
    if world == "lurga":
        return 7 + 8 * math.sin(3*x+.6) * math.cos(3*z-1) + 4*math.sin(5*y+2*z)
    return 7 + 10 * math.sin(3*x-1) * math.cos(2*z+.4) + 4*math.sin(5*y-x)


def surface_radius(world, direction):
    d = normalize(direction)
    radius = WORLDS[world]["radius_m"]
    h = base_height(world, d)
    for i in range(16):
        p = poi_direction(i)
        cosine = max(-1.0, min(1.0, dot(d, p)))
        distance = radius * math.acos(cosine)
        if distance < 27.0:
            t = max(0.0, min(1.0, (27.0-distance) / 8.0))
            t = t*t*(3-2*t)
            target = (radius + base_height(world, p)) / max(cosine, .1) - radius
            h = h*(1-t) + target*t
    return radius+h


def godot_to_blender(v):
    return (v[0], -v[2], v[1])


def blender_to_godot(v):
    return (v[0], v[2], -v[1])
