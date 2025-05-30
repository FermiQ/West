!
! Copyright (C) 2015-2025 M. Govoni
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
! This file is part of WEST.
!
! Contributors to this file:
! Marco Govoni
!
!-----------------------------------------------------------------------
SUBROUTINE apply_alpha_pv_to_m_wfcs(nbndval,m,f,g,alpha)
  !-----------------------------------------------------------------------
  !
  ! | g_i > = alpha * P_v | f_i > + | g_i >         forall i = 1:m
  !
  USE kinds,                ONLY : DP
  USE pwcom,                ONLY : npw,npwx
  USE mp_global,            ONLY : intra_bgrp_comm
  USE mp,                   ONLY : mp_sum
  USE control_flags,        ONLY : gamma_only
  USE noncollin_module,     ONLY : npol
  USE wavefunctions,        ONLY : evc
#if defined(__CUDA)
  USE west_gpu,             ONLY : ps_r,ps_c
  USE cublas
#endif
  !
  IMPLICIT NONE
  !
  ! I/O
  !
  INTEGER, INTENT(IN) :: nbndval,m
  COMPLEX(DP), INTENT(IN) :: alpha
  COMPLEX(DP), INTENT(IN) :: f(npwx*npol,m)
  COMPLEX(DP), INTENT(INOUT) :: g(npwx*npol,m)
  !
  ! Workspace
  !
  REAL(DP) :: alpha_r
#if !defined(__CUDA)
  REAL(DP), ALLOCATABLE :: ps_r(:,:)
  COMPLEX(DP), ALLOCATABLE :: ps_c(:,:)
#endif
  !
#if defined(__CUDA)
  CALL start_clock_gpu('alphapv')
#else
  CALL start_clock('alphapv')
#endif
  !
  ! ps = < evc | f >
  !
  IF( gamma_only ) THEN
     !
     alpha_r = REAL(alpha,KIND=DP)
     !
#if !defined(__CUDA)
     ALLOCATE( ps_r(nbndval,m) )
     ps_r = 0.0_DP
#endif
     !
     CALL glbrak_gamma( evc, f, ps_r, npw, npwx, nbndval, m, nbndval, npol)
     !
     !$acc host_data use_device(ps_r)
     CALL mp_sum(ps_r,intra_bgrp_comm)
     !$acc end host_data
     !
     !$acc host_data use_device(evc,ps_r,g)
     CALL DGEMM('N','N',2*npwx*npol,m,nbndval,alpha_r,evc,2*npwx*npol,ps_r,nbndval,1.0_DP,g,2*npwx*npol)
     !$acc end host_data
     !
#if !defined(__CUDA)
     DEALLOCATE( ps_r )
#endif
     !
  ELSE
     !
#if !defined(__CUDA)
     ALLOCATE( ps_c(nbndval,m) )
     ps_c = (0.0_DP,0.0_DP)
#endif
     !
     CALL glbrak_k( evc, f, ps_c, npw, npwx, nbndval, m, nbndval, npol)
     !
     !$acc host_data use_device(ps_c)
     CALL mp_sum(ps_c,intra_bgrp_comm)
     !$acc end host_data
     !
     !$acc host_data use_device(evc,ps_c,g)
     CALL ZGEMM('N','N',npwx*npol,m,nbndval,alpha,evc,npwx*npol,ps_c,nbndval,(1.0_DP,0.0_DP),g,npwx*npol)
     !$acc end host_data
     !
#if !defined(__CUDA)
     DEALLOCATE( ps_c )
#endif
     !
  ENDIF
  !
#if defined(__CUDA)
  CALL stop_clock_gpu('alphapv')
#else
  CALL stop_clock('alphapv')
#endif
  !
END SUBROUTINE
