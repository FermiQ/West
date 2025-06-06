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
SUBROUTINE do_dip()
  !-----------------------------------------------------------------------
  !
  USE control_flags,        ONLY : gamma_only
  USE kinds,                ONLY : DP
  USE westcom,              ONLY : iuwfc,lrwfc,l_skip_nl_part_of_hcomr,westpp_range,logfile
  USE mp_world,             ONLY : mpime,root
  USE mp_global,            ONLY : my_image_id,inter_image_comm,intra_bgrp_comm
  USE mp,                   ONLY : mp_bcast,mp_sum
  USE pwcom,                ONLY : npw,npwx,nbnd,current_spin,isk,xk,lsda,igk_k,current_k,ngk,&
                                 & nspin,et
  USE bar,                  ONLY : bar_type,start_bar_type,update_bar_type,stop_bar_type
  USE uspp_init,            ONLY : init_us_2
  USE io_push,              ONLY : io_push_title
  USE noncollin_module,     ONLY : npol
  USE cell_base,            ONLY : bg
  USE buffers,              ONLY : get_buffer
  USE types_bz_grid,        ONLY : k_grid
  USE json_module,          ONLY : json_file
  USE uspp,                 ONLY : vkb,nkb
  USE wavefunctions,        ONLY : evc
#if defined(__CUDA)
  USE west_gpu,             ONLY : allocate_gpu,deallocate_gpu,allocate_macropol_gpu,&
                                 & deallocate_macropol_gpu
#endif
  !
  IMPLICIT NONE
  !
  ! Workspace
  !
  INTEGER :: iks
  INTEGER :: ipol
  INTEGER :: icart
  INTEGER :: nstate
  INTEGER :: iunit
  REAL(DP), ALLOCATABLE :: dip_cryst_r(:,:,:)
  REAL(DP), ALLOCATABLE :: dip_cart_r(:,:,:)
  COMPLEX(DP), ALLOCATABLE :: dip_cryst_c(:,:,:)
  COMPLEX(DP), ALLOCATABLE :: dip_cart_c(:,:,:)
  COMPLEX(DP), ALLOCATABLE :: Hx_psi(:,:)
  CHARACTER(LEN=6) :: label_k
  TYPE(bar_type) :: barra
  TYPE(json_file) :: json
  !
  IF(nspin == 4) CALL errore('do_dip','nspin 4 not yet implemented',1)
  IF(westpp_range(2) > nbnd) CALL errore('do_dip','westpp_range(2) > nbnd',1)
  !
  nstate = westpp_range(2)-westpp_range(1)+1
  IF(gamma_only) THEN
     ALLOCATE(dip_cryst_r(nstate,nstate,3))
     !$acc enter data create(dip_cryst_r)
     ALLOCATE(dip_cart_r(nstate,nstate,3))
  ELSE
     ALLOCATE(dip_cryst_c(nstate,nstate,3))
     !$acc enter data create(dip_cryst_c)
     ALLOCATE(dip_cart_c(nstate,nstate,3))
  ENDIF
  ALLOCATE(Hx_psi(npwx*npol,nstate))
  !$acc enter data create(Hx_psi)
  !
#if defined(__CUDA)
  CALL allocate_gpu()
  CALL allocate_macropol_gpu(nstate)
#endif
  !
  IF(mpime == root) THEN
     CALL json%initialize()
     CALL json%load(filename=TRIM(logfile))
  ENDIF
  !
  CALL io_push_title('(D)ipole matrix')
  !
  CALL start_bar_type(barra,'westpp',k_grid%nps*3)
  !
  ! LOOP
  !
  DO iks = 1,k_grid%nps ! KPOINT-SPIN LOOP
     !
     ! ... Set k-point, spin, kinetic energy, needed by Hpsi
     !
     current_k = iks
     npw = ngk(iks)
     IF(lsda) current_spin = isk(iks)
     CALL g2_kin(iks)
     !
     ! ... More stuff needed by the hamiltonian: nonlocal projectors
     !
#if defined(__CUDA)
     IF(nkb > 0) CALL init_us_2(ngk(iks),igk_k(1,iks),xk(1,iks),vkb,.TRUE.)
#else
     IF(nkb > 0) CALL init_us_2(ngk(iks),igk_k(1,iks),xk(1,iks),vkb,.FALSE.)
#endif
     !
     ! ... read in wavefunctions
     !
     IF(k_grid%nps > 1) THEN
        IF(my_image_id == 0) CALL get_buffer(evc,lrwfc,iuwfc,iks)
        CALL mp_bcast(evc,0,inter_image_comm)
        !$acc update device(evc)
     ENDIF
     !
     DO ipol = 1,3
        !
        CALL commut_Hx_psi(iks,nstate,ipol,evc(:,westpp_range(1):westpp_range(2)),Hx_psi,&
        & l_skip_nl_part_of_hcomr)
        !
        IF(gamma_only) THEN
           CALL glbrak_gamma(evc(:,westpp_range(1):westpp_range(2)),Hx_psi,&
           & dip_cryst_r(:,:,ipol),npw,npwx,nstate,nstate,nstate,npol)
        ELSE
           CALL glbrak_k(evc(:,westpp_range(1):westpp_range(2)),Hx_psi,dip_cryst_c(:,:,ipol),&
           & npw,npwx,nstate,nstate,nstate,npol)
        ENDIF
        !
        CALL update_bar_type(barra,'westpp',1)
        !
     ENDDO
     !
     IF(gamma_only) THEN
        !$acc update host(dip_cryst_r)
        !
        CALL mp_sum(dip_cryst_r,intra_bgrp_comm)
        !
        dip_cart_r = 0._DP
        DO icart = 1,3
           DO ipol = 1,3
              dip_cart_r(:,:,icart) = dip_cart_r(:,:,icart)+bg(icart,ipol)*dip_cryst_r(:,:,ipol)
           ENDDO
        ENDDO
     ELSE
        !$acc update host(dip_cryst_c)
        !
        CALL mp_sum(dip_cryst_c,intra_bgrp_comm)
        !
        dip_cart_c = (0._DP,0._DP)
        DO icart = 1,3
           DO ipol = 1,3
              dip_cart_c(:,:,icart) = dip_cart_c(:,:,icart)+bg(icart,ipol)*dip_cryst_c(:,:,ipol)
           ENDDO
        ENDDO
     ENDIF
     !
     IF(mpime == root) THEN
        !
        WRITE(label_k,'(I6.6)') iks
        !
        CALL json%add('output.D.K'//label_k//'.weight',k_grid%weight(iks))
        CALL json%add('output.D.K'//label_k//'.energies',et(:,iks))
        !
        IF(gamma_only) THEN
           CALL json%add('output.D.K'//label_k//'.dipole.x',&
           & RESHAPE(dip_cart_r(:,:,1),[nstate*nstate]))
           CALL json%add('output.D.K'//label_k//'.dipole.y',&
           & RESHAPE(dip_cart_r(:,:,2),[nstate*nstate]))
           CALL json%add('output.D.K'//label_k//'.dipole.z',&
           & RESHAPE(dip_cart_r(:,:,3),[nstate*nstate]))
        ELSE
           CALL json%add('output.D.K'//label_k//'.dipole.x.re',&
           & REAL(RESHAPE(dip_cart_c(:,:,1),[nstate*nstate]),KIND=DP))
           CALL json%add('output.D.K'//label_k//'.dipole.x.im',&
           & AIMAG(RESHAPE(dip_cart_c(:,:,1),[nstate*nstate])))
           CALL json%add('output.D.K'//label_k//'.dipole.y.re',&
           & REAL(RESHAPE(dip_cart_c(:,:,2),[nstate*nstate]),KIND=DP))
           CALL json%add('output.D.K'//label_k//'.dipole.y.im',&
           & AIMAG(RESHAPE(dip_cart_c(:,:,2),[nstate*nstate])))
           CALL json%add('output.D.K'//label_k//'.dipole.z.re',&
           & REAL(RESHAPE(dip_cart_c(:,:,3),[nstate*nstate]),KIND=DP))
           CALL json%add('output.D.K'//label_k//'.dipole.z.im',&
           & AIMAG(RESHAPE(dip_cart_c(:,:,3),[nstate*nstate])))
        ENDIF
        !
     ENDIF
     !
  ENDDO
  !
  CALL stop_bar_type(barra,'westpp')
  !
  IF(gamma_only) THEN
     !$acc exit data delete(dip_cryst_r)
     DEALLOCATE(dip_cryst_r)
     DEALLOCATE(dip_cart_r)
  ELSE
     !$acc exit data delete(dip_cryst_c)
     DEALLOCATE(dip_cryst_c)
     DEALLOCATE(dip_cart_c)
  ENDIF
  !$acc exit data delete(Hx_psi)
  DEALLOCATE(Hx_psi)
  !
#if defined(__CUDA)
  CALL deallocate_gpu()
  CALL deallocate_macropol_gpu()
#endif
  !
  IF(mpime == root) THEN
     OPEN(NEWUNIT=iunit,FILE=TRIM(logfile))
     CALL json%print(iunit)
     CLOSE(iunit)
     CALL json%destroy()
  ENDIF
  !
END SUBROUTINE
