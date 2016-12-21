
set N; # Nos
set O; # Origem
set D; # Destino
set NotD := N diff D; # Nos que nao sao destino
set NotOD := NotD diff O; # Nos que nao sao origem nem destino

set A within N cross N; # Arestas
set S{i in N} := {j in N: (i,j) in A}; # Saída
set E{i in N} := {j in N: (j,i) in A}; # Entrada

# for{i in N} for {j in S[i]} printf "S[%d] %d\n", i,j;
# for{i in N} for {j in E[i]} printf "E[%d] %d\n", i,j;

param c1{A}; # Custo
param c2{A};

var x1{A}, binary;
var x2{A}, binary;

minimize obj: sum{(i,j) in A} (c1[i,j] * x1[i,j] + c2[i,j] * x2[i,j]);

# Conservacao do Fluxo
s.t. cons1O1{i in O}: sum{j in S[i]} x1[i,j] = 1;
s.t. cons1O2{i in O}: sum{j in E[i]} x2[j,i] = 0;
s.t. cons1NotOD{i in NotOD}: sum{j in S[i]} x1[i,j] - sum{j in E[i]} x2[j,i] = 0;
s.t. cons1D1{i in D}: sum{j in S[i]} x1[i,j] = 0;
s.t. cons1D2{i in D}: sum{j in E[i]} x2[j,i] = 1;

s.t. cons2O1{i in O}: sum{j in S[i]} x2[i,j] = 1;
s.t. cons2O2{i in O}: sum{j in E[i]} x1[j,i] = 0;
s.t. cons2NotOD{i in NotOD}: sum{j in S[i]} x2[i,j] - sum{j in E[i]} x1[j,i] = 0;
s.t. cons2D1{i in D}: sum{j in S[i]} x2[i,j] = 0;
s.t. cons2D2{i in D}: sum{j in E[i]} x1[j,i] = 1;

# Apenas 1 radio
s.t. umradio{i in NotD}: sum{j in E[i]} x1[j,i] + sum{j in E[i]} x2[j,i] <= 1;
# Paridade
s.t. paridade: sum{(i,j) in A} x1[i,j] - sum{(i,j) in A} x2[i,j] = 0;

end;
