
set N; # Nos
set O; # Origem
set D; # Destino
set NotD := N diff D; # Nos que nao sao destino
set NotOD := NotD diff O; # Nos que nao sao origem nem destino

set A within N cross N; # Arestas
set S{i in N} := {j in N: (i,j) in A}; # Saída
set E{i in N} := {j in N: (j,i) in A}; # Entrada

param c1{A}; # Custo
param c2{A};

var x1{A}, binary;
var x2{A}, binary;

minimize obj: sum{(i,j) in A} (c1[i,j] * x1[i,j] + c2[i,j] * x2[i,j]);

# Conservacao do Fluxo
s.t. cons1O{i in O}: sum{j in S[i]} x1[i,j] + sum{j in S[i]} x2[i,j] - sum{j in E[i]} x2[j,i] - sum{j in E[i]} x1[j,i] = 1;
s.t. cons1NotOD{i in NotOD}: sum{j in S[i]} x1[i,j] + sum{j in S[i]} x2[i,j] - sum{j in E[i]} x2[j,i] - sum{j in E[i]} x1[j,i] = 0;
s.t. cons1D{i in D}: sum{j in S[i]} x1[i,j] + sum{j in S[i]} x2[i,j] - sum{j in E[i]} x2[j,i] - sum{j in E[i]} x1[j,i] = -1;
# Alternar
s.t. alt1{i in NotOD}: sum{j in E[i]} x1[j,i] + sum{j in S[i]} x1[i,j] <= 1;
s.t. alt2{i in NotOD}: sum{j in E[i]} x2[j,i] + sum{j in S[i]} x2[i,j] <= 1;
end;
