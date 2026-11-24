# Seguimiento de un robot de 2 eslabones en caída

Programa en Python que detecta, en tiempo real, tres post-its de color pegados a un
brazo de 2 eslabones y registra cómo cambian su posición y sus ángulos mientras cae.

| Marcador | Color   | Función                  |
|----------|---------|--------------------------|
| Base     | Verde   | Hombro, punto fijo       |
| Codo     | Rosa    | Unión entre los eslabones |
| Punta    | Naranja | Efector final            |

## Qué hace en cada frame

1. **Segmenta** cada color en el espacio HSV y limpia la máscara con filtros morfológicos.
2. **Filtra candidatos**: solo acepta manchas compactas y casi cuadradas, para descartar
   manos, brazos u otros objetos del mismo tono.
3. **Valida la geometría**: cada marcador debe estar a la distancia esperada del anterior
   (base → codo → punta) y no puede dar saltos bruscos respecto al frame previo.
4. **Calcula los ángulos** `q1` y `q2` y la velocidad de la punta.
5. **Muestra** el resultado en una ventana con los puntos, los eslabones, la estela de cada
   marcador y una mini gráfica de `q1` y `q2`.
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
| `video1.mp4` … `video3.mp4` | Videos de la caída del robot                              |
| `Foto de colores .jpeg`   | Foto de referencia para calibrar los colores y los eslabones |
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

El programa pregunta qué video ejecutar:

```
Que video quieres ejecutar? (1, 2 o 3):
```

### Otras opciones

Se agregan al final del comando anterior:

| Opción               | Qué hace                                      |
|----------------------|-----------------------------------------------|
| `--source 0`         | Cámara en vivo                                |
| `--source otro.mp4`  | Cualquier otro video                          |
| `--calibrar`         | Clic en un post-it para ver su HSV            |
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

Al iniciar, el programa usa `Foto de colores .jpeg` para ajustarse solo:

- **Colores:** mide los valores HSV reales de cada post-it, así no dependen de rangos
  escritos a mano. El de más arriba en la foto es la base, el del medio el codo y el de
  más abajo la punta.
- **Longitud de los eslabones:** la mide en "lados de post-it", por lo que no depende de
  la resolución del video.

Si cambia la iluminación y algún color falla, usa `--calibrar` y haz clic sobre el
post-it para imprimir su valor HSV en la terminal. Luego ajusta `COLORES` al inicio de
`main.py`.

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

Si un marcador no se detecta, sus celdas quedan vacías. En video, `t` sale del tiempo del
archivo (`frame / fps`); con cámara, del reloj real.

## Ajustes finos

Constantes al inicio de `main.py`:

| Constante     | Efecto                                                          |
|---------------|-----------------------------------------------------------------|
| `COLORES`     | Rangos HSV iniciales de cada marcador                           |
| `AREA_MIN`    | Área mínima (px²) para aceptar una mancha                       |
| `TOL_LONG`    | Tolerancia sobre la longitud esperada de cada eslabón           |
| `SALTO_MAX`   | Desplazamiento máximo entre frames (fracción del ancho)         |
| `PERDIDO_MAX` | Frames sin ver un marcador antes de olvidar su posición previa  |

## Problemas comunes

- **Detecta la mano o el brazo de una persona como el punto naranja:** el filtro de forma
  y de longitud de eslabones lo evita en los videos incluidos. Si pasa con otro video,
  recalibra con `--calibrar` y estrecha el rango de tono del naranja.
- **Un marcador no se detecta:** revisa la iluminación y ajusta su rango HSV.
