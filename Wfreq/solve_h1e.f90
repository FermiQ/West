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
SUBROUTINE solve_h1e()
  !-----------------------------------------------------------------------
  !
  USE westcom,              ONLY : n_bands,n_pairs,qp_bands,ijpmap,sigma_hf_full,sigma_corr_full,&
                                 & sigma_exx_full,sigma_hf,sigma_sc_eqpsec,sigma_exx,qdet_dc
  USE kinds,                ONLY : DP
  USE pwcom,                ONLY : nspin,et
  USE io_push,              ONLY : io_push_title
  USE wfreq_db,             ONLY : qdet_db_write_h1e
  USE distribution_center,  ONLY : kpt_pool
  !
  IMPLICIT NONE
  !
  INTEGER :: is,is_g,ib
  REAL(DP), ALLOCATABLE :: h1e(:,:)
  !
  ! Compute 1-electron integrals h1e(i,j) = <i|H|j> where H is the 1-electron Hamiltonian
  !
  CALL io_push_title("h1e")
  !
  ! You need to modify this file if you plan to use things like
  ! Hubbard U, electric field, meta-GGA, etc. that are not considered here.
  ! If any of these are requested, the code stops in wfreq_setup.
  !
  ALLOCATE(h1e(n_pairs,nspin))
  h1e(:,:) = 0._DP
  !
  DO is = 1, kpt_pool%nloc
     is_g = kpt_pool%l2g(is)
     DO ib = 1, n_bands
        h1e(ijpmap(ib,ib),is_g) = et(qp_bands(ib,is_g),is)
     ENDDO
  ENDDO
  !
  IF(qdet_dc == 'HFDC' .OR. qdet_dc == 'hfdc') THEN
     !
     ! Hartree Fock double counting
     !
     ! H1e = H^{KS} - V^{H}_{dc} - V^{X}_{dc}
     !
     CALL compute_hartree_double_counting(h1e)
     CALL compute_fock_double_counting(h1e)
     !
  ELSE
     !
     ! Exact double counting
     !
     ! H1e = H^{KS} - V_{xc} + \Sigma^{x} + \Sigma^{c}
     !
     DO is = 1, kpt_pool%nloc
        is_g = kpt_pool%l2g(is)
        h1e(:,is_g) = h1e(:,is_g)+sigma_hf_full(:,is_g)+REAL(sigma_corr_full(:,is_g),KIND=DP)
     ENDDO
     !
     ! H1e = H^{KS} - V_{xc} + \Sigma^{x} + \Sigma^{c} - V^{H}_{dc}
     !
     CALL compute_hartree_double_counting(h1e)
     !
     CALL calc_exx2(sigma_exx, .TRUE.)
     !
     ! H1e = H^{KS} - V_{xc} + \Sigma^{x} + \Sigma^{c} - V^{H}_{dc} - \Sigma^{x}_{dc}
     !
     h1e(:,:) = h1e - sigma_exx_full
     !
     ! Call solve_qp with
     ! l_secant = .FALSE.
     ! l_generate_plot = .FALSE.
     ! l_QDET = .TRUE.
     !
     CALL solve_qp(.FALSE., .FALSE., .TRUE.)
     !
     ! H1e = H^{KS} - V_{xc} + \Sigma^{x} + \Sigma^{c} - V^{H}_{dc} - \Sigma^{x}_{dc} - \Sigma^{c}_{dc}
     !
     h1e(:,:) = h1e - REAL(sigma_corr_full,KIND=DP)
     !
  ENDIF
  !
  CALL qdet_db_write_h1e(h1e)
  !
  DEALLOCATE(h1e)
  !
END SUBROUTINE
!
!-----------------------------------------------------------------------
SUBROUTINE compute_hartree_double_counting(h1e_tmp)
  !-----------------------------------------------------------------------
  !
  USE kinds,                ONLY : DP
  USE pwcom,                ONLY : nspin
  USE westcom,              ONLY : n_bands,qp_bands,n_pairs,ijpmap,eri_w,occupation
  USE distribution_center,  ONLY : kpt_pool
  USE mp,                   ONLY : mp_sum
  USE mp_global,            ONLY : inter_pool_comm
  !
  IMPLICIT NONE
  !
  REAL(DP), INTENT(INOUT) :: h1e_tmp(n_pairs,nspin)
  !
  INTEGER :: is1, is1_g, is2, ipair, jpair, jb
  REAL(DP) :: prefactor
  REAL(DP), ALLOCATABLE :: occ(:,:)
  !
  ! if nspin=1, a factor of 2 has to be applied to the occupation
  !
  IF(nspin == 1) THEN
     prefactor = 2._DP
  ELSE
     prefactor = 1._DP
  ENDIF
  !
  ! get global copy of occupation
  !
  ALLOCATE(occ(n_bands,nspin))
  !
  occ(:,:) = 0._DP
  DO is1 = 1, kpt_pool%nloc
     is1_g = kpt_pool%l2g(is1)
     DO jb = 1, n_bands
        occ(jb,is1_g) = occupation(qp_bands(jb,is1_g),is1)
     ENDDO
  ENDDO
  !
  CALL mp_sum(occ,inter_pool_comm)
  !
  DO is1 = 1, kpt_pool%nloc
     is1_g = kpt_pool%l2g(is1)
     DO ipair = 1, n_pairs
        DO is2 = 1, nspin
           DO jb = 1, n_bands
              jpair = ijpmap(jb,jb)
              h1e_tmp(ipair,is1_g) = h1e_tmp(ipair,is1_g) &
              & - prefactor*eri_w(ipair,jpair,is1_g,is2)*occ(jb,is2)
           ENDDO
        ENDDO
     ENDDO
  ENDDO
  !
  CALL mp_sum(h1e_tmp,inter_pool_comm)
  !
  DEALLOCATE(occ)
  !
END SUBROUTINE
!
!-----------------------------------------------------------------------
SUBROUTINE compute_fock_double_counting(h1e_tmp)
  !-----------------------------------------------------------------------
  !
  USE kinds,                ONLY : DP
  USE pwcom,                ONLY : nspin
  USE westcom,              ONLY : n_bands,qp_bands,n_pairs,ijpmap,eri_w,occupation
  USE distribution_center,  ONLY : kpt_pool
  USE mp,                   ONLY : mp_sum
  USE mp_global,            ONLY : inter_pool_comm
  !
  IMPLICIT NONE
  !
  REAL(DP), INTENT(INOUT) :: h1e_tmp(n_pairs,nspin)
  !
  INTEGER :: is1, is1_g, is2, ipair, jpair, ijpair, ib, jb, kb
  REAL(DP) :: prefactor
  REAL(DP), ALLOCATABLE :: occ(:,:)
  !
  ! get global copy of occupation
  !
  ALLOCATE(occ(n_bands,nspin))
  !
  occ(:,:) = 0._DP
  DO is1 = 1, kpt_pool%nloc
     is1_g = kpt_pool%l2g(is1)
     DO jb = 1, n_bands
        occ(jb,is1_g) = occupation(qp_bands(jb,is1_g),is1)
     ENDDO
  ENDDO
  !
  CALL mp_sum(occ,inter_pool_comm)
  !
  DO is1 = 1, kpt_pool%nloc
     is1_g = kpt_pool%l2g(is1)
     DO ib = 1, n_bands
        DO jb = ib, n_bands
           DO kb = 1, n_bands
              ipair = ijpmap(ib,kb)
              jpair = ijpmap(jb,kb)
              ijpair = ijpmap(ib,jb)
              h1e_tmp(ijpair,is1_g) = h1e_tmp(ijpair,is1_g) &
              & + eri_w(ipair,jpair,is1_g,is1_g)*occ(kb,is1_g)
           ENDDO
        ENDDO
     ENDDO
  ENDDO
  !
  CALL mp_sum(h1e_tmp,inter_pool_comm)
  !
  DEALLOCATE(occ)
  !
END SUBROUTINE
