# Seguimiento de un robot de 2 eslabones en caída

Programa en Python que detecta, en tiempo real, tres marcadores circulares de color
(post-its con una cruz negra) pegados a un brazo de 2 eslabones y registra cómo cambian
su posición, sus ángulos y la velocidad de la punta mientras cae.

| Marcador | Color   | Función                  |
|----------|---------|--------------------------|
| Base     | Verde   | Hombro, punto fijo       |
| Codo     | Rosa    | Unión entre los eslabones |
| Punta    | Naranja | Efector final            |

## Qué hace en cada frame

1. **Segmenta** cada color en el espacio HSV y limpia la máscara con filtros morfológicos.
2. **Filtra candidatos**: solo acepta manchas compactas y regulares (con forma de círculo
   o cuadrado), para descartar manos, brazos u otros objetos del mismo tono.
3. **Valida la geometría**: cada marcador debe estar a la distancia esperada del anterior
   (base → codo → punta) y no puede dar saltos bruscos respecto al frame previo.
4. **Calcula los ángulos** `q1` y `q2` y la velocidad de la punta (en px/s y cm/s).
5. **Muestra** el resultado en una ventana con los puntos, los eslabones, la estela de cada
   marcador, el tiempo, los ángulos, la velocidad en cm/s y una mini gráfica de `q1` y `q2`.
6. **Registra** cada frame en un archivo CSV.

## Requisitos

- Python 3.14 (funciona también en versiones recientes)
- `opencv-python`, `numpy` y `matplotlib` (listadas en `requirements.txt`)

### Instalación

Ejecuta estos comandos dentro de la carpeta del proyecto.

**macOS / Linux** (Terminal):

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

**Windows** (PowerShell o CMD):

```powershell
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

Si en Windows `py` no se reconoce, usa `python` en su lugar.

## Archivos del proyecto

| Archivo                   | Para qué sirve                                              |
|---------------------------|-------------------------------------------------------------|
| `main.py`                 | Programa principal                                          |
| `vid1.mp4` … `vid7.mp4`   | Videos de la caída del robot                                |
| `foto_de_colores.jpeg`    | Foto de referencia para calibrar los colores y la escala    |
| `requirements.txt`        | Dependencias                                                |
| `registro_<video>.csv`    | Resultado de cada ejecución (se genera al terminar)         |

## Uso

**macOS / Linux:**

```bash
.venv/bin/python main.py
```

**Windows:**

```powershell
.venv\Scripts\python main.py
```

Si instalaste las dependencias sin entorno virtual, usa `python3 main.py` (macOS / Linux)
o `py main.py` (Windows).

El programa pregunta qué video ejecutar:

```
Que video quieres ejecutar? (1 al 7):
```

### Otras opciones

Se agregan al final del comando anterior:

| Opción               | Qué hace                                      |
|----------------------|-----------------------------------------------|
| `--source 0`         | Cámara en vivo                                |
| `--source otro.mp4`  | Cualquier otro video                          |
| `--calibrar`         | Clic en un marcador para ver su HSV           |
| `--sin-foto`         | No calibrar con la foto de referencia         |
| `--foto otra.jpg`    | Otra foto de referencia                       |
| `--salida datos.csv` | Nombre del CSV de salida                      |

Por ejemplo, para usar la cámara en vivo:

**macOS / Linux:**

```bash
.venv/bin/python main.py --source 0
```

**Windows:**

```powershell
.venv\Scripts\python main.py --source 0
```

Si se pasa `--source`, el programa no pregunta por el video.

### Teclas en la ventana

| Tecla       | Acción                              |
|-------------|-------------------------------------|
| `q` / `ESC` | Salir y guardar el CSV              |
| `ESPACIO`   | Pausar / reanudar                   |
| `r`         | Reiniciar el registro y las estelas |

## Calibración

Al iniciar, el programa usa `foto_de_colores.jpeg` para ajustarse solo:

- **Colores:** mide los valores HSV reales de cada marcador, así no dependen de rangos
  escritos a mano. El de más arriba en la foto es la base, el del medio el codo y el de
  más abajo la punta.
- **Tamaño del marcador:** usa la distancia base → codo (15 cm) como regla para saber
  cuánto mide un marcador en cm (≈ 2.8 cm). Sin foto se usa `LADO_CM` = 2.9 cm.

Si cambia la iluminación y algún color falla, usa `--calibrar` y haz clic sobre el
marcador para imprimir su valor HSV en la terminal. Luego ajusta `COLORES` al inicio de
`main.py`.

## Longitud de los eslabones

Las distancias entre centros de marcadores, medidas con regla, están fijas en `LONG_CM`
al inicio de `main.py`. El programa nunca las modifica, ni siquiera al calibrar con la foto:

| Eslabón       | Distancia |
|---------------|-----------|
| Base → codo   | 15 cm     |
| Codo → punta  | 10 cm     |

Se usan para dos cosas:

- **Descartar detecciones falsas:** las pasa a "tamaños de marcador" (15 ÷ 2.8 ≈ 5.3 y
  10 ÷ 2.8 ≈ 3.5), así la comprobación no depende de qué tan cerca esté la cámara. Un
  marcador se acepta si está a esa distancia del anterior, con un margen de ±45 %.
- **Convertir la velocidad a cm/s:** en cada frame mide cuántos píxeles hay entre base y
  codo y lo divide entre 15 cm para obtener la escala (px/cm). Usa la mediana de los
  últimos 30 frames para que sea estable.

Los ángulos `q1` y `q2` no usan estas longitudes.

## Ángulos

Se calculan con las posiciones de los tres marcadores en la imagen:

- **`q1`**: ángulo del eslabón 1 (base → codo) respecto a la vertical hacia abajo.
  Con el robot colgando recto, `q1 = 0°`. Es positivo cuando el codo se desplaza hacia
  la derecha de la imagen.
- **`q2`**: ángulo del eslabón 2 (codo → punta) relativo al eslabón 1, entre −180° y 180°.
  Con el robot recto, `q2 = 0°`.

## Archivo CSV

Cada fila es un frame:

| Columna                              | Significado                                  |
|--------------------------------------|----------------------------------------------|
| `t`                                  | Tiempo en segundos                           |
| `frame`                              | Número de frame                              |
| `base_x`, `base_y`                   | Posición del marcador verde (px)             |
| `codo_x`, `codo_y`                   | Posición del marcador rosa (px)              |
| `punta_x`, `punta_y`                 | Posición del marcador naranja (px)           |
| `q1_deg`, `q2_deg`                   | Ángulos en grados                            |
| `vel_punta_px_s`                     | Velocidad de la punta en píxeles por segundo |
| `vel_punta_cm_s`                     | Velocidad de la punta en cm por segundo      |

Si un marcador no se detecta, sus celdas quedan vacías. En video, `t` sale del tiempo del
archivo (`frame / fps`); con cámara, del reloj real.

## Ajustes finos

Constantes al inicio de `main.py`:

| Constante     | Efecto                                                          |
|---------------|-----------------------------------------------------------------|
| `COLORES`     | Rangos HSV iniciales de cada marcador                           |
| `LONG_CM`     | Distancias reales entre marcadores: 15 y 10 cm                  |
| `LADO_CM`     | Tamaño del marcador (cm) si no se usa la foto                   |
| `AREA_MIN`    | Área mínima (px²) para aceptar una mancha                       |
| `TOL_LONG`    | Tolerancia sobre la longitud esperada de cada eslabón (0.45 = ±45 %) |
| `SALTO_MAX`   | Desplazamiento máximo entre frames (fracción del ancho)         |
| `PERDIDO_MAX` | Frames sin ver un marcador antes de olvidar su posición previa  |

## Problemas comunes

- **Detecta la mano o el brazo de una persona como el punto naranja:** el filtro de forma
  y de longitud de eslabones lo evita en los videos incluidos. Si pasa con otro video,
  recalibra con `--calibrar` y estrecha el rango de tono del naranja.
- **Un marcador no se detecta:** revisa la iluminación y ajusta su rango HSV.
