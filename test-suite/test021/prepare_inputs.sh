#!/bin/bash

${WGET} http://www.quantum-simulation.org/potentials/sg15_oncv/upf/C_ONCV_PBE-1.0.upf
${WGET} http://www.quantum-simulation.org/potentials/sg15_oncv/upf/H_ONCV_PBE-1.0.upf
${WGET} http://www.quantum-simulation.org/potentials/sg15_oncv/upf/O_ONCV_PBE-1.0.upf

cat > pw.in << EOF
&control
calculation  = 'scf'
restart_mode = 'from_scratch'
pseudo_dir   = './'
outdir       = './'
prefix       = 'test'
/
&system
ibrav           = 1
celldm(1)       = 20
nat             = 4
ntyp            = 3
ecutwfc         = 25
nbnd            = 30
input_dft       = 'pbe0'
/
&electrons
diago_full_acc = .true.
/
ATOMIC_SPECIES
C 12.0107  C_ONCV_PBE-1.0.upf
H 1.0079  H_ONCV_PBE-1.0.upf
O 16.00  O_ONCV_PBE-1.0.upf
ATOMIC_POSITIONS crystal
C        0.452400000   0.500000000   0.500000000
H        0.397141530   0.411608770   0.500000000
H        0.397141530   0.588391230   0.500000000
O        0.565022174   0.500000000   0.500000000
K_POINTS gamma
EOF


cat > wbse_init.in << EOF
input_west:
  qe_prefix: test
  west_prefix: test
  outdir: ./

wbse_init_control:
  wbse_init_calculation: S
  solver: TDDFT
EOF


cat > wbse.in << EOF
input_west:
  qe_prefix: test
  west_prefix: test
  outdir: ./

wbse_init_control:
  wbse_init_calculation: S
  solver: TDDFT

wbse_control:
  wbse_calculation: D
  n_liouville_eigen: 4
  n_liouville_times: 10
  trev_liouville: 0.00000001
  trev_liouville_rel: 0.000001
  l_pre_shift: True
  l_forces: True
  forces_state: 1
EOF
