import argparse
import csv
import math
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np

# Rangos HSV iniciales; la foto de referencia los reajusta.
COLORES = {
    "base":  {"bgr": (0, 220, 0),     "rangos": [((30, 90, 100), (50, 255, 255))]},   # verde lima
    "codo":  {"bgr": (180, 0, 255),   "rangos": [((150, 80, 100), (179, 255, 255)),
                                                 ((0, 120, 120), (4, 255, 255))]},     # rosa
    "punta": {"bgr": (0, 140, 255),   "rangos": [((8, 100, 120), (24, 255, 255))]},   # naranja
}
AQUI = Path(__file__).resolve().parent
AREA_MIN = 150          # area minima en px^2
HISTORIAL = 300         # muestras en la grafica
KERNEL = np.ones((5, 5), np.uint8)


def mascara(hsv, rangos):
    m = np.zeros(hsv.shape[:2], np.uint8)
    for lo, hi in rangos:
        m |= cv2.inRange(hsv, np.array(lo), np.array(hi))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, KERNEL)
    return cv2.morphologyEx(m, cv2.MORPH_CLOSE, KERNEL)


def calibrar_desde_foto(ruta):
    """Ajusta los rangos HSV y la longitud de los eslabones con la foto de referencia.

    Los post-its se ordenan por altura: arriba = base, medio = codo, abajo = punta.
    """
    img = cv2.imread(str(ruta))
    if img is None:
        print(f"[aviso] no se pudo leer {ruta}; se usan los rangos por defecto")
        return
    hsv = cv2.cvtColor(cv2.GaussianBlur(img, (5, 5), 0), cv2.COLOR_BGR2HSV)
    hallados = []
    for nombre, c in COLORES.items():
        cs, _ = cv2.findContours(mascara(hsv, c["rangos"]), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not cs:
            print(f"[aviso] no se hallo '{nombre}' en la foto")
            return
        cnt = max(cs, key=cv2.contourArea)
        relleno = np.zeros(hsv.shape[:2], np.uint8)
        cv2.drawContours(relleno, [cnt], -1, 255, -1)
        hallados.append((cv2.boundingRect(cnt)[1], nombre, relleno))
    hallados.sort(key=lambda t: t[0])
    orden = list(COLORES)
    for (_, _, relleno), nombre in zip(hallados, orden):
        px = hsv[(relleno > 0) & (hsv[..., 2] > 90)]   # ignora la cruz negra
        (h0, s0, v0), (h1, _, _) = (np.percentile(px, 2, axis=0), np.percentile(px, 98, axis=0))
        lo = (max(int(h0) - 3, 0), max(int(s0) - 15, 90), max(int(v0) - 40, 90))
        hi = (min(int(h1) + 6, 179), 255, 255)
        COLORES[nombre]["rangos"] = [(lo, hi)]
        print(f"[calibrado] {nombre}: HSV {lo} -> {hi}")

    # Tamano del marcador en cm, usando la distancia real base -> codo como regla
    info = []
    for _, _, relleno in hallados:
        M = cv2.moments(relleno, True)
        info.append(((M["m10"] / M["m00"], M["m01"] / M["m00"]), math.sqrt(M["m00"])))
    px_por_cm = math.dist(info[0][0], info[1][0]) / LONG_CM["base_codo"]
    lado_cm = (info[0][1] + info[1][1] + info[2][1]) / 3 / px_por_cm
    actualizar_geom(lado_cm)
    print(f"[calibrado] marcador: {lado_cm:.2f} cm; eslabones: {LONG_CM['base_codo']:g} cm "
          f"({GEOM['base_codo']:.2f} marcadores) y {LONG_CM['codo_punta']:g} cm "
          f"({GEOM['codo_punta']:.2f} marcadores)")


# Distancias reales entre centros de marcadores, medidas con regla (cm).
LONG_CM = {"base_codo": 15.0, "codo_punta": 10.0}
LADO_CM = 2.9            # tamano aproximado del marcador (cm); la foto lo recalcula


def actualizar_geom(lado_cm):
    """Pasa las longitudes de cm a 'tamanos de marcador', que no dependen del zoom del video."""
    for k, cm in LONG_CM.items():
        GEOM[k] = cm / lado_cm


GEOM = {}
actualizar_geom(LADO_CM)
TOL_LONG = 0.45          # tolerancia sobre la longitud del eslabon
SALTO_MAX = 0.25         # salto maximo entre frames (fraccion del ancho)
PERDIDO_MAX = 15         # frames sin ver el marcador antes de olvidarlo


def candidatos(m):
    """Manchas con forma de post-it (compactas y casi cuadradas); descarta brazos y manos."""
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out = []
    for c in cs:
        area = cv2.contourArea(c)
        if area < AREA_MIN:
            continue
        (_, _), (w, h), _ = cv2.minAreaRect(c)      # tolera post-its girados
        if min(w, h) < 1:
            continue
        solidez = area / max(cv2.contourArea(cv2.convexHull(c)), 1)
        relleno = area / (w * h)
        if not (max(w, h) / min(w, h) <= 1.5 and solidez > 0.7 and relleno > 0.65):
            continue
        M = cv2.moments(c)
        out.append({"p": (M["m10"] / M["m00"], M["m01"] / M["m00"]), "lado": math.sqrt(area)})
    return out


class Seguidor:
    """Elige el candidato de cada color que respeta la longitud de los eslabones y la continuidad."""

    def __init__(self):
        self.prev = {k: None for k in COLORES}
        self.perdido = {k: 0 for k in COLORES}

    def _elegir(self, nombre, cands, ancho, ref=None, long_esp=None):
        buenos = []
        for c in cands:
            if ref is not None:                       # longitud del eslabon
                d = math.dist(c["p"], ref["p"]) / ref["lado"]
                if abs(d - long_esp) > TOL_LONG * long_esp:
                    continue
                err = abs(d - long_esp)
            else:
                err = -c["lado"]                      # base: la mancha mas grande
            if self.prev[nombre] is not None:         # continuidad
                salto = math.dist(c["p"], self.prev[nombre]["p"])
                if salto > SALTO_MAX * ancho:
                    continue
                err = salto
            buenos.append((err, c))
        if not buenos:
            self.perdido[nombre] += 1
            if self.perdido[nombre] > PERDIDO_MAX:
                self.prev[nombre] = None
            return None
        self.perdido[nombre] = 0
        self.prev[nombre] = min(buenos, key=lambda t: t[0])[1]
        return self.prev[nombre]

    def actualizar(self, hsv):
        ancho = hsv.shape[1]
        cands = {k: candidatos(mascara(hsv, c["rangos"])) for k, c in COLORES.items()}
        base = self._elegir("base", cands["base"], ancho)
        codo = self._elegir("codo", cands["codo"], ancho, base, GEOM["base_codo"]) if base else None
        punta = self._elegir("punta", cands["punta"], ancho, codo, GEOM["codo_punta"]) if codo else None
        return {k: (v["p"] if v else None) for k, v in zip(COLORES, (base, codo, punta))}


def angulos(p0, p1, p2):
    """q1: eslabon 1 respecto a la vertical hacia abajo; q2: eslabon 2 relativo al 1 (grados)."""
    a1 = math.atan2(p1[0] - p0[0], p1[1] - p0[1])
    a2 = math.atan2(p2[0] - p1[0], p2[1] - p1[1])
    q2 = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
    return math.degrees(a1), math.degrees(q2)


def dibujar_grafica(frame, q1s, q2s, origen=(10, 10), tam=(300, 140)):
    x0, y0 = origen
    w, h = tam
    roi = frame[y0:y0 + h, x0:x0 + w]
    roi[:] = (roi * 0.35).astype(np.uint8)
    cv2.line(roi, (0, h // 2), (w, h // 2), (120, 120, 120), 1)
    for serie, col in ((q1s, (0, 220, 0)), (q2s, (0, 140, 255))):
        pts = [(int(i * w / HISTORIAL), int(h / 2 - v * (h / 2) / 180))
               for i, v in enumerate(serie) if v is not None]
        if len(pts) > 1:
            cv2.polylines(roi, [np.array(pts, np.int32)], False, col, 2)
    cv2.putText(roi, "q1 (verde)  q2 (naranja)  +-180 deg", (4, 14),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)


def calibrar_click(evento, x, y, _flags, datos):
    if evento == cv2.EVENT_LBUTTONDOWN and datos["hsv"] is not None:
        print(f"HSV en ({x},{y}) = {datos['hsv'][y, x]}")


def elegir_video():
    """Pregunta en la terminal que video ejecutar."""
    while True:
        try:
            r = input("Que video quieres ejecutar? (1 al 7): ").strip()
        except (EOFError, KeyboardInterrupt):
            raise SystemExit("\nCancelado.")
        if r in [str(i) for i in range(1, 8)]:
            ruta = AQUI / f"vid{r}.mp4"
            if ruta.exists():
                print(f"Ejecutando {ruta.name}...")
                return ruta
            print(f"No existe {ruta.name}.")
        else:
            print("Opcion invalida, escribe un numero del 1 al 7.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=None,
                    help="ruta de video o indice de camara; si se omite, se pregunta cual video usar")
    ap.add_argument("--foto", default=str(AQUI / "foto_de_colores.jpeg"),
                    help="foto de referencia para calibrar los colores")
    ap.add_argument("--sin-foto", action="store_true", help="no calibrar con la foto")
    ap.add_argument("--calibrar", action="store_true", help="clic para imprimir HSV")
    ap.add_argument("--salida", default=None, help="CSV de salida (por defecto registro_<video>.csv)")
    args = ap.parse_args()

    if args.source is None:
        args.source = str(elegir_video())
    if args.salida is None:
        nombre = Path(args.source).stem if not args.source.isdigit() else "camara"
        args.salida = str(AQUI / f"registro_{nombre}.csv")

    if not args.sin_foto:
        calibrar_desde_foto(args.foto)

    fuente = int(args.source) if args.source.isdigit() else args.source
    cap = cv2.VideoCapture(fuente)
    if not cap.isOpened():
        raise SystemExit(f"No se pudo abrir la fuente: {args.source}")
    es_video = not isinstance(fuente, int)
    fps_src = cap.get(cv2.CAP_PROP_FPS) or 30

    datos = {"hsv": None}
    cv2.namedWindow("Robot 2 eslabones")
    if args.calibrar:
        cv2.setMouseCallback("Robot 2 eslabones", calibrar_click, datos)

    filas, trail = [], {k: deque(maxlen=60) for k in COLORES}
    q1s, q2s = deque(maxlen=HISTORIAL), deque(maxlen=HISTORIAL)
    t0 = time.perf_counter()
    seguidor = Seguidor()
    prev = None
    escalas = deque(maxlen=30)   # ultimas mediciones de px/cm
    pausa = False
    frame_idx = 0

    while True:
        if not pausa:
            ok, frame = cap.read()
            if not ok:
                break
            frame_idx += 1
            # video: tiempo del archivo; camara: reloj real
            t = frame_idx / fps_src if es_video else time.perf_counter() - t0

            hsv = cv2.cvtColor(cv2.GaussianBlur(frame, (5, 5), 0), cv2.COLOR_BGR2HSV)
            datos["hsv"] = hsv
            pos = seguidor.actualizar(hsv)

            fila = {"t": round(t, 4), "frame": frame_idx}
            for k, p in pos.items():
                fila[f"{k}_x"], fila[f"{k}_y"] = (round(p[0], 1), round(p[1], 1)) if p else (None, None)
                if p:
                    trail[k].append((int(p[0]), int(p[1])))

            q1 = q2 = None
            if all(pos.values()):
                q1, q2 = angulos(pos["base"], pos["codo"], pos["punta"])
            fila["q1_deg"], fila["q2_deg"] = (round(q1, 2), round(q2, 2)) if q1 is not None else (None, None)

            # escala px/cm: el eslabon base -> codo mide LONG_CM["base_codo"]
            if pos["base"] and pos["codo"]:
                escalas.append(math.dist(pos["base"], pos["codo"]) / LONG_CM["base_codo"])

            # velocidad de la punta (px/s y cm/s)
            vel = vel_cm = None
            if prev and pos["punta"] and prev[1]["punta"] and t > prev[0]:
                dx = pos["punta"][0] - prev[1]["punta"][0]
                dy = pos["punta"][1] - prev[1]["punta"][1]
                vel = math.hypot(dx, dy) / (t - prev[0])
                if escalas:
                    vel_cm = vel / float(np.median(escalas))
            fila["vel_punta_px_s"] = round(vel, 1) if vel is not None else None
            fila["vel_punta_cm_s"] = round(vel_cm, 1) if vel_cm is not None else None
            prev = (t, pos)
            filas.append(fila)
            q1s.append(q1)
            q2s.append(q2)

            for k, c in COLORES.items():
                pts = list(trail[k])
                if len(pts) > 1:
                    cv2.polylines(frame, [np.array(pts, np.int32)], False, c["bgr"], 2)
                if pos[k]:
                    cv2.circle(frame, (int(pos[k][0]), int(pos[k][1])), 7, c["bgr"], -1)
                    cv2.circle(frame, (int(pos[k][0]), int(pos[k][1])), 9, (255, 255, 255), 1)
            if all(pos.values()):
                p = [tuple(map(int, pos[k])) for k in ("base", "codo", "punta")]
                cv2.line(frame, p[0], p[1], (255, 255, 255), 2)
                cv2.line(frame, p[1], p[2], (255, 255, 255), 2)
            txt = (f"t={t:6.2f}s  q1={q1:7.1f}  q2={q2:7.1f}  v={vel_cm or 0:6.1f}cm/s"
                   if q1 is not None else f"t={t:6.2f}s  marcador no detectado")
            h = frame.shape[0]
            cv2.putText(frame, txt, (10, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 3)
            cv2.putText(frame, txt, (10, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            dibujar_grafica(frame, q1s, q2s)
            cv2.imshow("Robot 2 eslabones", frame)

        k = cv2.waitKey(1 if not es_video else max(1, int(1000 / fps_src))) & 0xFF
        if k in (ord("q"), 27):
            break
        if k == ord(" "):
            pausa = not pausa
        if k == ord("r"):
            filas.clear(); q1s.clear(); q2s.clear()
            for d in trail.values():
                d.clear()

    cap.release()
    cv2.destroyAllWindows()

    if filas:
        with open(args.salida, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(filas[0]))
            w.writeheader()
            w.writerows(filas)
        print(f"{len(filas)} frames guardados en {Path(args.salida).resolve()}")


if __name__ == "__main__":
    main()
