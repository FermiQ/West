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
SUBROUTINE precondition_m_wfcts (m,f,pf,eprec)
  !-----------------------------------------------------------------------
  !
  USE kinds,                 ONLY : DP
  USE wvfct,                 ONLY : g2kin
  USE noncollin_module,      ONLY : noncolin,npol
  USE pwcom,                 ONLY : npw,npwx
  !
  IMPLICIT NONE
  !
  ! I/O
  !
  INTEGER,INTENT(IN) :: m
  COMPLEX(DP),INTENT(IN) :: f(npwx*npol,m)
  COMPLEX(DP),INTENT(OUT) :: pf(npwx*npol,m)
  REAL(DP),INTENT(IN) :: eprec(m)
  !
  ! Workspace
  !
  INTEGER :: ibnd, ig
  !
  !$acc parallel loop collapse(2) present(pf,f,g2kin,eprec)
  DO ibnd = 1,m
     DO ig = 1,npwx
        IF(ig <= npw) THEN
           pf(ig,ibnd) = f(ig,ibnd)/MAX(1._DP,g2kin(ig)/eprec(ibnd))
           IF(noncolin) THEN
              pf(npwx+ig,ibnd) = f(npwx+ig,ibnd)/MAX(1._DP,g2kin(ig)/eprec(ibnd))
           ENDIF
        ELSE
           pf(ig,ibnd) = 0._DP
           IF(noncolin) THEN
              pf(npwx+ig,ibnd) = 0._DP
           ENDIF
        ENDIF
     ENDDO
  ENDDO
  !$acc end parallel
  !
END SUBROUTINE
