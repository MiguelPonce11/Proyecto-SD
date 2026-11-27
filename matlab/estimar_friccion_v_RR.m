%% ESTIMACION DE FRICCION VISCOSA DEL PENDULO DOBLE
% Usa los videos 2 y 5, reservados para identificar b1 y b2.
% En cada ventana se estiman q y dq con un polinomio local y se simula
% el movimiento. Se buscan los coeficientes que minimizan el error angular.
% Los datos ausentes se excluyen del error; no se interpolan.
% Salida normal: solo viscosa1 y viscosa2 en Command Window.
% Colocar este archivo junto a registro_vid2.csv y registro_vid5.csv.

clear; clc;

%% 1. PARAMETROS FISICOS FIJOS
p.g = 9.81;               % [m/s^2]
p.l1 = 0.150;             % Distancia entre articulaciones [m]
p.m1 = 0.04632;           % Masa del conjunto 1 reportada por CAD [kg]
p.m2 = 0.02573;           % Masa del conjunto 2 reportada por CAD [kg]
p.lc1 = 0.075;            % Aproximacion por simetria [m]
p.lc2 = 0.032;            % Medicion aproximada por equilibrio [m]
p.I1 = 226206.95 * 1e-9;  % Inercia en CM1, eje z [kg*m^2]
p.I2 =  27180.91 * 1e-9;  % Inercia en CM2, eje z [kg*m^2]

valores = [p.g,p.l1,p.m1,p.m2,p.lc1,p.lc2,p.I1,p.I2];
assert(all(isfinite(valores)) && all(valores > 0), ...
    'Los parametros fisicos deben ser finitos y positivos.');

%% 2. CONFIGURACION
% CSV usados exclusivamente para identificar la friccion.
cfg.archivos = {'registro_vid2.csv', 'registro_vid5.csv'};
cfg.inicios = [5.3331+0.5, 9.3729+0.5];  % [s] dentro de cada video (provisionales)
cfg.duracion = 6;               % [s] despues de cada inicio

cfg.Tw = 1.5;       % Horizonte de prediccion de cada ventana [s]
cfg.paso = 0.2;     % Separacion entre inicios de ventana [s]
cfg.margen = 0.3;   % Margen al comienzo del tramo [s]; debe ser >= cfg.hw.
cfg.hw = 0.10;      % Semiancho del ajuste local para estimar q y dq [s]
cfg.grado = 3;      % Grado del polinomio local
cfg.minMuestras = 8;% Minimo de cuadros por ventana

assert(cfg.duracion > 0 && cfg.Tw > 0 && cfg.paso > 0);
assert(cfg.margen >= cfg.hw, 'cfg.margen debe ser >= cfg.hw.');
assert(cfg.grado >= 1 && cfg.grado == floor(cfg.grado));

carpeta = fileparts(mfilename('fullpath'));
if isempty(carpeta)
    carpeta = pwd;
end

%% 3. LECTURA Y ARMADO DE VENTANAS
nV = numel(cfg.archivos);
Vk = cell(1,nV);
for k = 1:nV
    d = leerPrueba(fullfile(carpeta,cfg.archivos{k}), ...
        cfg.inicios(k),cfg.duracion);
    Vk{k} = armarVentanas(d,cfg);
    if numel(Vk{k}) < 5
        error('Muy pocas ventanas validas en %s.',cfg.archivos{k});
    end
end
Vall = [Vk{:}];   % Todas las ventanas de todos los videos

%% 4. ESTIMACION DE b1 Y b2
% b = escala*exp(z) mantiene b positivo.
escala = 1e-4;
bmin = 1e-9;      % "practicamente cero" (nunca exactamente cero)
bmax = 0.1;       % Limite numerico amplio; no es una propiedad medida
opcionesODE = odeset('RelTol',1e-6,'AbsTol',1e-8);
opcionesOpt = optimset('Display','off','MaxIter',150, ...
    'MaxFunEvals',300,'TolX',1e-3,'TolFun',1e-9);

% Comprobar la integracion ANTES de optimizar: un error de programacion
% o de lectura debe ser visible, no ocultarse como un mal ajuste.
costoVentanas([1e-4;1e-4],p,Vall,opcionesODE);

% Barrido inicial: selecciona los puntos desde los que se optimiza.
g = logspace(-6,-2,9);
J = NaN(numel(g));
for i = 1:numel(g)
    for j = 1:numel(g)
        try
            J(i,j) = costoVentanas([g(i);g(j)],p,Vall,opcionesODE);
        catch
            J(i,j) = NaN;
        end
    end
end
if all(isnan(J(:)))
    error('Ningun par del barrido produjo una simulacion valida.');
end

% 4b. Refinamiento con fminsearch desde los mejores puntos del barrido.
[~,orden] = sort(J(:));              % NaN quedan al final
nSem = min(2,sum(isfinite(J(:))));
objetivo = @(z) costoZ(z,escala,bmin,bmax,p,Vall,opcionesODE);
mejorCosto = Inf;
mejorZ = [];
mejorFlag = NaN;
for m = 1:nSem
    [i,j] = ind2sub(size(J),orden(m));
    z0 = log([g(i);g(j)]/escala);
    [z,costo,flag] = fminsearch(objetivo,z0,opcionesOpt);
    if costo < mejorCosto
        mejorCosto = costo;
        mejorZ = z(:);
        mejorFlag = flag;
    end
end
if isempty(mejorZ) || ~isfinite(mejorCosto) || mejorCosto >= 1e6
    error('Ninguna busqueda produjo un ajuste valido.');
end
bPool = escala*exp(mejorZ);

%% 5. RESULTADO
% Avisos si la optimizacion no converge o llega a un limite.
if mejorFlag <= 0
    warning('La mejor busqueda alcanzo su limite de calculo.');
end
if any(bPool < 10*bmin) || any(bPool > bmax/2)
    warning('Hay un coeficiente cerca de un limite; no es definitivo.');
end
viscosa1 = bPool(1);
viscosa2 = bPool(2);
fprintf('viscosa1 = %.8g; %% [N*m*s/rad]\n',viscosa1);
fprintf('viscosa2 = %.8g; %% [N*m*s/rad]\n',viscosa2);

%% FUNCIONES LOCALES
function d = leerPrueba(archivo,inicio,duracion)
    if exist(archivo,'file') ~= 2
        error('No se encuentra el CSV: %s',archivo);
    end
    tabla = readtable(archivo);
    requeridas = {'t','q1_deg','q2_deg'};
    if ~all(ismember(requeridas,tabla.Properties.VariableNames))
        error('Faltan columnas t, q1_deg o q2_deg en %s.',archivo);
    end
    t = tabla.t(:);
    if numel(t) < 10 || any(~isfinite(t)) || any(diff(t) <= 0)
        error('Tiempos no validos en %s.',archivo);
    end
    if inicio < t(1) || inicio > t(end)
        error('El inicio solicitado esta fuera del CSV: %s.',archivo);
    end

    ang = [tabla.q1_deg,tabla.q2_deg];
    ang(~isfinite(ang)) = NaN;

    % q1 SOLO necesita base y codo; puede recuperarse si falta la punta.
    % Convenio de imagen: x derecha, y hacia abajo.
    columnas = {'base_x','base_y','codo_x','codo_y'};
    if all(ismember(columnas,tabla.Properties.VariableNames))
        dx = tabla.codo_x - tabla.base_x;
        dy = tabla.codo_y - tabla.base_y;
        coordenadas = [tabla.base_x,tabla.base_y,tabla.codo_x,tabla.codo_y];
        disponibles = all(isfinite(coordenadas),2) & hypot(dx,dy) > 0;
        recuperadas = ~isfinite(ang(:,1)) & disponibles;
        ang(recuperadas,1) = rad2deg(atan2(dx(recuperadas),dy(recuperadas)));
    end

    [~,j] = min(abs(t-inicio));
    tInicio = t(j);
    sel = t >= tInicio & t <= tInicio + duracion;
    tc = t(sel);
    q = deg2rad(ang(sel,:));
    q(:,1) = q(:,1) - pi/2;

    % Sin unwrap a traves de huecos; todo se compara modulo 2*pi.
    q = atan2(sin(q),cos(q));
    mascara = isfinite(q);
    if numel(tc) < 20 || any(sum(mascara,1) < 10)
        error('Tramo muy corto o con muy pocas mediciones en %s.',archivo);
    end
    dt = median(diff(t));
    if tc(end)-tc(1) < duracion-2*dt
        warning('El CSV termina antes de la duracion solicitada: %s.',archivo);
    end

    d.t = tc-tInicio;      % Se conservan TODOS los tiempos, incluidos huecos.
    d.q = q;               % NaN no se sustituyen ni se interpolan.
end

function V = armarVentanas(d,cfg)
    % Cada ventana: tiempos relativos al inicio (t(1) = 0), mediciones,
    % y estado inicial [q1;q2;dq1;dq2] estimado localmente de los datos.
    t = d.t;
    q = d.q;
    dt = median(diff(t));
    salto = max(1,round(cfg.paso/dt));
    k = ceil(cfg.margen/dt) + 1;
    V = {};
    while k <= numel(t)
        tk = t(k);
        if tk + cfg.Tw > t(end) + 1e-9
            break;
        end
        idx = find(t >= tk-1e-9 & t <= tk+cfg.Tw+1e-9);
        x0 = estadoLocal(t,q,tk,cfg.hw,cfg.grado);
        if ~isempty(x0) && numel(idx) >= cfg.minMuestras
            v.t = t(idx) - tk;
            v.q = q(idx,:);
            v.x0 = x0;
            V{end+1} = v; %#ok<AGROW>
        end
        k = k + salto;
    end
end

function x0 = estadoLocal(t,q,tc,hw,grado)
    % Ajuste polinomial local alrededor de tc, por articulacion,
    % usando solo las muestras validas. Devuelve [] si hay pocas.
    x0 = zeros(4,1);
    for j = 1:2
        m = abs(t-tc) <= hw+1e-9 & isfinite(q(:,j));
        if sum(m) < max(grado+2,5)
            x0 = [];
            return;
        end
        tt = t(m) - tc;
        qq = q(m,j);
        ref = qq(1);
        qq = ref + atan2(sin(qq-ref),cos(qq-ref));  % desenvolver localmente
        c = polyfit(tt,qq,grado);
        x0(j) = c(end);       % q en tc
        x0(j+2) = c(end-1);   % dq en tc
    end
end

function costo = costoVentanas(b,p,V,opcionesODE)
    s = [0,0];
    n = [0,0];
    for i = 1:numel(V)
        v = V{i};
        x = simularVentana(p,b,v,opcionesODE);
        e = atan2(sin(x(:,1:2)-v.q),cos(x(:,1:2)-v.q));
        e = e(2:end,:);                 % el primer punto es la condicion inicial
        ok = isfinite(v.q(2:end,:));
        e(~ok) = 0;
        s = s + sum(e.^2,1);
        n = n + sum(ok,1);
    end
    if any(n == 0)
        error('Sin mediciones validas en las ventanas.');
    end
    mse = s./n;       % Igual peso por articulacion
    costo = sum(mse);
end

function costo = costoZ(z,escala,bmin,bmax,p,V,opcionesODE)
    penalizacion = 1e6;
    costo = penalizacion;
    if any(~isfinite(z))
        return;
    end
    exceso = max(log(bmin/escala)-z,0) + max(z-log(bmax/escala),0);
    if any(exceso > 0)
        costo = penalizacion + sum(exceso.^2);
        return;
    end
    try
        c = costoVentanas(escala*exp(z(:)),p,V,opcionesODE);
        if isfinite(c)
            costo = c;
        end
    catch
        costo = penalizacion;
    end
end

function x = simularVentana(p,b,v,opcionesODE)
    [tout,x] = ode45(@(t,x) dinamica(x,p,b),v.t,v.x0,opcionesODE);
    if numel(tout) ~= numel(v.t) || any(~isfinite(x(:)))
        error('La integracion de una ventana no termino.');
    end
end

function dx = dinamica(x,p,b)
    q1 = x(1); q2 = x(2);
    dq = x(3:4);
    dq1 = dq(1); dq2 = dq(2);
    a = p.m2*p.l1*p.lc2;

    M11 = p.I1+p.I2+p.m1*p.lc1^2 ...
        + p.m2*(p.l1^2+p.lc2^2)+2*a*cos(q2);
    M12 = p.I2+p.m2*p.lc2^2+a*cos(q2);
    M22 = p.I2+p.m2*p.lc2^2;
    M = [M11,M12;M12,M22];

    h = a*sin(q2);
    C = [-h*dq2,-h*(dq1+dq2);h*dq1,0];
    G1 = p.g*(p.m1*p.lc1 + p.m2*p.l1)*cos(q1) + ...
         p.m2*p.g*p.lc2*cos(q1 + q2);
    G2 = p.m2*p.g*p.lc2*cos(q1 + q2);
    G = [G1; G2];
    F = b(:).*dq;

    ddq = M \ (-C*dq-G-F);
    dx = [dq;ddq];
end
