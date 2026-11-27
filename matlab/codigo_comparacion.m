%% RR VERTICAL: comparación entre la simulación del modelo y los datos experimentales
clear; close all; clc;

%% 1. CONFIGURACION DEL VIDEO Y CONDICIONES INICIALES
archivo_csv = 'registro_vid3.csv'; % nombre del archivo .csv
inicio_video = 1.7;              % [s] aproximacion a la liberacion del video, este dato cambia para cada video entre 0.5 y 2 seg
duracion = 60;                    % [s] desde el inicio hasta final de simulación

% q1 desde la vertical hacia abajo.
% q2 es relativo al primer eslabon. Ambos angulos en grados.
q_inicial_vertical_grados = [-90; 0]; 
dq_inicial = [0; 0];                % [rad/s] se suelta desde reposo.

% Conversion automatica a la referencia INTERNA (horizontal) del modelo.
q_inicial_grados = q_inicial_vertical_grados(:) - [90; 0];

%% 2. PARAMETROS FISICOS (UNIDADES SI)
L1 = 0.150;              % Distancia entre articulaciones [m].
LC1 = 0.075;             % Centro de masa 1, aproximado por simetria [m].
LC2 = 0.032;             % Centro de masa 2, medido por equilibrio [m].
masa1 = 0.04632;         % Masa del conjunto 1, datos de CAD [kg].
masa2 = 0.02573;         % Masa del conjunto 2, datos de CAD [kg].
inercia1 = 2.2620695e-4; % Inercia en CM1, eje perpendicular al plano [kg*m^2].
inercia2 = 2.718091e-5;  % Inercia en CM2, eje perpendicular al plano [kg*m^2].
gravedad = 9.81;         % Magnitud positiva [m/s^2].
viscosa1 = 1.0e-4;       % b1 fijado con las pruebas de identificacion [N*m*s/rad].
viscosa2 = 1.55e-4;      % b2 fijado con las pruebas de identificacion [N*m*s/rad].
% Coulomb no fue identificada y se omite.
% L2 no interviene por separado.

% comprobación de que sean válidos los datos
fisicos = [L1,LC1,LC2,masa1,masa2,inercia1,inercia2,gravedad];
assert(all(isfinite(fisicos)) && all(fisicos > 0), ...
    'Los parametros fisicos deben ser finitos y positivos.');
assert(all(isfinite([viscosa1,viscosa2])) && all([viscosa1,viscosa2] >= 0), ...
    'Los coeficientes viscosos deben ser finitos y no negativos.');
assert(isscalar(inicio_video) && isfinite(inicio_video) && ...
       isscalar(duracion) && isfinite(duracion) && duracion > 0, ...
    'Revisar inicio_video y duracion.');
assert(numel(q_inicial_grados) == 2 && numel(dq_inicial) == 2 && ...
       all(isfinite([q_inicial_grados(:); dq_inicial(:)])), ...
    'Las condiciones iniciales deben contener dos angulos y dos velocidades.');

%% 3. MODELO SIMBOLICO Y VERIFICACION DE EULER-LAGRANGE
syms q1 q2 dq1 dq2 ddq1 ddq2 real
syms l1 lc1 lc2 m1 m2 I1 I2 g positive
syms b1 b2 real
q = [q1; q2];
dq = [dq1; dq2];
ddq = [ddq1; ddq2];

% materiz de inercias
M11 = m1*lc1^2 + m2*l1^2 + m2*lc2^2 ...
    + 2*m2*l1*lc2*cos(q2) + I1 + I2;
M12 = m2*l1*lc2*cos(q2) + m2*lc2^2 + I2;
M22 = m2*lc2^2 + I2;
M = [M11, M12; M12, M22];

% matriz de fuerzas centrífugas 
C = [-m2*l1*lc2*sin(q2)*dq2, -m2*l1*lc2*sin(q2)*(dq1+dq2);
      m2*l1*lc2*sin(q2)*dq1, 0];

% energía cinética
T = simplify(dq.'*M*dq/2);
% energía potencial
U = m1*g*lc1*(1+sin(q1)) ...
    + m2*g*(l1*(1+sin(q1)) + lc2*(1+sin(q1+q2)));
% U = 0 cuando ambos cuelgan: q1 = -pi/2, q2 = 0.
Lag = T - U;
G1 = g*(m1*lc1+m2*l1)*cos(q1) + m2*g*lc2*cos(q1+q2);
G2 = m2*g*lc2*cos(q1+q2);
G = [G1; G2];
Ff = [b1*dq1; b2*dq2]; % El torque fisico de friccion es -Ff.
ecuaciones = M*ddq + C*dq + G + Ff == sym([0; 0]); % tau = 0.

pLag = jacobian(Lag,dq).';
dpLag_dt = jacobian(pLag,q)*dq + jacobian(pLag,dq)*ddq;
EL = simplify(dpLag_dt - jacobian(Lag,q).');
residuo_EL = simplify(EL - (M*ddq + C*dq + G));
assert(isequal(residuo_EL,sym([0; 0])), 'Revisar el modelo simbolico.');
disp('Verificacion Euler-Lagrange: residuo cero.');
disp('M(q) ='); disp(M);
disp('C(q,dq) ='); disp(C);
disp('G(q) ='); disp(G);
disp('Ff(dq) ='); disp(Ff);
disp('Lagrangiano T-U ='); disp(Lag);
disp('Ecuaciones sin torque de actuadores ='); disp(ecuaciones);

%% 4. FUNCIONES NUMERICAS: SUSTITUIR PARAMETROS UNA SOLA VEZ
parametros = [l1,lc1,lc2,m1,m2,I1,I2,g,b1,b2];
valores = [L1,LC1,LC2,masa1,masa2,inercia1,inercia2,gravedad,viscosa1,viscosa2];
Mfun = matlabFunction(subs(M,parametros,valores),'Vars',{q});
Cfun = matlabFunction(subs(C,parametros,valores),'Vars',{q,dq});
Gfun = matlabFunction(subs(G,parametros,valores),'Vars',{q});
Ffun = matlabFunction(subs(Ff,parametros,valores),'Vars',{dq});
Ufun = matlabFunction(subs(U,parametros,valores),'Vars',{q});

%% 5. LECTURA DEL CSV Y SELECCION DEL TIEMPO
ruta_csv = archivo_csv;
if ~isfile(ruta_csv)
    ruta_csv = fullfile(fileparts(mfilename('fullpath')), archivo_csv);
end
assert(isfile(ruta_csv), 'No se encontro el CSV. Revisar archivo_csv en la seccion 1.');
datos = readtable(ruta_csv);
requeridas = {'t','q1_deg','q2_deg'};
assert(all(ismember(requeridas,datos.Properties.VariableNames)), ...
    'Faltan columnas t, q1_deg o q2_deg en el CSV.');

t_csv = datos.t(:);
assert(numel(t_csv) >= 3 && all(isfinite(t_csv)) && all(diff(t_csv) > 0), ...
    'Los tiempos del CSV deben ser finitos y estrictamente crecientes.');
assert(inicio_video >= t_csv(1) && inicio_video < t_csv(end), ...
    'inicio_video debe estar dentro del intervalo del CSV.');
ang = [datos.q1_deg, datos.q2_deg];
ang(~isfinite(ang)) = NaN;

recuperadas = false(size(t_csv));
columnas = {'base_x','base_y','codo_x','codo_y'};
if all(ismember(columnas,datos.Properties.VariableNames))
    dx = datos.codo_x - datos.base_x;
    dy = datos.codo_y - datos.base_y;
    coords = [datos.base_x,datos.base_y,datos.codo_x,datos.codo_y];
    disponibles = all(isfinite(coords),2) & hypot(dx,dy) > 0;
    recuperadas = ~isfinite(ang(:,1)) & disponibles;
    ang(recuperadas,1) = rad2deg(atan2(dx(recuperadas),dy(recuperadas)));
end

[~,indice_inicio] = min(abs(t_csv-inicio_video));
t_inicio = t_csv(indice_inicio);
seleccion = t_csv >= t_inicio & t_csv <= t_inicio+duracion;
t_exp = t_csv(seleccion)-t_inicio;
assert(numel(t_exp) >= 3 && t_exp(end) > 0, 'El intervalo seleccionado es demasiado corto.');
tiempo_final = t_exp(end); % Duracion efectiva disponible en el CSV.

% Pasar las mediciones a la referencia INTERNA del modelo.
q_exp = deg2rad(ang(seleccion,:));
q_exp(:,1) = q_exp(:,1)-pi/2;
q_exp = atan2(sin(q_exp),cos(q_exp));
validas = isfinite(q_exp);
assert(all(sum(validas,1) >= 10), 'Muy pocas mediciones validas para comparar.');

fprintf('\nInicio aproximado en el video: %.4f s; duracion: %.4f s\n', ...
    t_inicio,tiempo_final);
fprintf('Mediciones validas: q1 %d/%d; q2 %d/%d\n', ...
    sum(validas(:,1)),numel(t_exp),sum(validas(:,2)),numel(t_exp));
fprintf('q1 recuperadas desde coordenadas en este tramo: %d\n',sum(recuperadas(seleccion)));

%% 6. CONDICIONES NOMINALES E INTEGRACION CONTINUA
% La postura y la velocidad iniciales son las fijadas en la seccion 1.
% No se estiman con mediciones posteriores ni se reinicia durante la caida.
x0 = [deg2rad(q_inicial_grados(:)); dq_inicial(:)];
fprintf('q inicial elegida, desde vertical: [%.2f; %.2f] grados\n', ...
    q_inicial_vertical_grados(1),q_inicial_vertical_grados(2));
fprintf('q inicial del modelo, desde horizontal: [%.2f; %.2f] grados\n', ...
    q_inicial_grados(1),q_inicial_grados(2));
fprintf('dq inicial: [%.2f; %.2f] rad/s\n',dq_inicial(1),dq_inicial(2));

% ode45 devuelve la solucion en los tiempos solicitados (t_exp).
% Internamente usa pasos adaptativos.
opciones = odeset('RelTol',1e-8,'AbsTol',1e-10,'MaxStep',0.01);
[t,x] = ode45(@(t,x) dinamica_RR(t,x,Mfun,Cfun,Gfun,Ffun), ...
             t_exp,x0,opciones);
assert(numel(t) == numel(t_exp) && all(isfinite(x(:))), ...
    'La integracion no completo el intervalo. Revisar los mensajes de ode45.');
q_hist = x(:,1:2);
dq_hist = x(:,3:4);

%% 7. ERROR ANGULAR: SOLO DONDE HAY MEDICIONES
% La diferencia circular evita interpretar +180 y -180 como posturas distintas.
diferencia = q_hist-q_exp;
error_angular = atan2(sin(diferencia),cos(diferencia));
rmse = zeros(1,2);
for j = 1:2
    rmse(j) = rad2deg(sqrt(mean(error_angular(validas(:,j),j).^2)));
end
fprintf('\nComparacion con %s:\n',archivo_csv);
fprintf('Error RMS: q1 = %.3f grados; q2 = %.3f grados\n',rmse(1),rmse(2));

%% 8. ENERGIAS Y BALANCE SIN TORQUE DE ACTUADORES
Ec = zeros(size(t));
Ep = zeros(size(t));
potencia_perdida = zeros(size(t));
for k = 1:numel(t)
    qk = q_hist(k,:).';
    dqk = dq_hist(k,:).';
    Ec(k) = 0.5*dqk.'*Mfun(qk)*dqk;
    Ep(k) = Ufun(qk);
    potencia_perdida(k) = dqk.'*Ffun(dqk);
end
E = Ec+Ep;
energia_disipada = cumtrapz(t,potencia_perdida);
balance = E+energia_disipada-E(1);
% El residuo incluye errores de integracion y de cuadratura de cumtrapz.
fprintf('Maximo residuo del balance energetico: %.3e J\n',max(abs(balance)));

%% 9. GRAFICAS: REFERENCIA VERTICAL EN AMBAS CURVAS
% El RMS se calculo arriba.
q_exp_graf = q_exp;
q_sim_graf = q_hist;
q_exp_graf(:,1) = q_exp_graf(:,1)+pi/2;
q_sim_graf(:,1) = q_sim_graf(:,1)+pi/2;
q_exp_graf = rad2deg(atan2(sin(q_exp_graf),cos(q_exp_graf)));
q_sim_graf = rad2deg(atan2(sin(q_sim_graf),cos(q_sim_graf)));
% Interrumpir lineas al cruzar entre +180 y -180, sin alterar los datos del RMS.
q_sim_linea = q_sim_graf;
saltos = [false(1,2); abs(diff(q_sim_graf,1,1)) > 180];
q_sim_linea(saltos) = NaN;


figure('Name','Comparación experimental','Color','w');
etiquetas = {'q_1 [grados]', ...
             'q_2 [grados]'};
for j = 1:2
    subplot(2,1,j);
    plot(t_exp,q_exp_graf(:,j),'k.','MarkerSize',8);
    hold on;
    plot(t,q_sim_linea(:,j),'r-','LineWidth',1.3);
    grid on; grid minor;
    ylim([-120,120]);
    xlim([0,tiempo_final]);
    xlabel('Tiempo [s]','FontSize',20);
    ylabel(etiquetas{j},'FontSize',20);
    legend('Experimental','Simulación','Location','best','FontSize',15);
    title(sprintf('%s: articulacion %d (RMS %.1f deg)',archivo_csv,j,rmse(j)), ...
          'Interpreter','none','FontSize',20);
end

%% FUNCION LOCAL
function dx = dinamica_RR(~,x,Mfun,Cfun,Gfun,Ffun)
    q_actual = x(1:2);
    dq_actual = x(3:4);
    M_actual = Mfun(q_actual);
    C_actual = Cfun(q_actual,dq_actual);
    G_actual = Gfun(q_actual);
    F_actual = Ffun(dq_actual);

    % M*ddq + C*dq + G + Ff = 0: sin torque de actuadores.
    lado_derecho = -C_actual*dq_actual-G_actual-F_actual;
    % La barra inversa resuelve M*ddq = lado_derecho sin formar inv(M).
    ddq_actual = M_actual \ lado_derecho;
    dx = [dq_actual; ddq_actual];
end
