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
MODULE class_idistribute
  !-----------------------------------------------------------------------
  !
  IMPLICIT NONE
  !
  PRIVATE
  !
  INTEGER,PUBLIC,PARAMETER :: IDIST_CYC = 1
  INTEGER,PUBLIC,PARAMETER :: IDIST_BLK = 2
  !
  TYPE,PUBLIC :: idistribute
     !
     INTEGER :: nloc = 0
     INTEGER :: nlocx = 0
     INTEGER :: nglob = 0
     INTEGER :: scheme = IDIST_CYC
     INTEGER :: myoffset = 0
     INTEGER :: nlevel = 0
     INTEGER :: mylevelid = 0
     INTEGER :: mpicomm = 0
     CHARACTER(1) :: info = ' '
     !
     CONTAINS
     !
     PROCEDURE :: init => idistribute_init
     PROCEDURE :: g2l => idistribute_g2l
     PROCEDURE :: l2g => idistribute_l2g
     PROCEDURE :: copyto => idistribute_copyto
     !
  END TYPE idistribute
  !
  CONTAINS
  !
  SUBROUTINE idistribute_init(this,n,level,label,lverbose,scheme)
    !
    USE mp_global,   ONLY : my_image_id,nimage,inter_image_comm,&
                          & my_pool_id,npool,inter_pool_comm,&
                          & my_bgrp_id,nbgrp,inter_bgrp_comm,&
                          & me_bgrp,nproc_bgrp,intra_bgrp_comm
    USE mp_world,    ONLY : mpime,world_comm,nproc
    USE io_push,     ONLY : io_push_title,io_push_value,io_push_bar
    !
    IMPLICIT NONE
    !
    ! I/O
    !
    CLASS(idistribute),INTENT(OUT) :: this
    INTEGER,INTENT(IN) :: n
    CHARACTER(1),INTENT(IN) :: level
    CHARACTER(*),INTENT(IN) :: label
    LOGICAL,INTENT(IN) :: lverbose
    INTEGER,INTENT(IN),OPTIONAL :: scheme
    !
    ! Workspace
    !
    INTEGER :: mylevelid,nlevel,level_comm
    INTEGER :: nloc,nlocx,nglob,nloc_min,myoffset
    CHARACTER(1) :: info
    !
    SELECT CASE(level)
    CASE('W','w')
       !
       mylevelid  = mpime
       nlevel     = nproc
       level_comm = world_comm
       info       = 'w'
       !
    CASE('I','i')
       !
       mylevelid  = my_image_id
       nlevel     = nimage
       level_comm = inter_image_comm
       info       = 'i'
       !
    CASE('P','p')
       !
       mylevelid  = my_pool_id
       nlevel     = npool
       level_comm = inter_pool_comm
       info       = 'p'
       !
    CASE('B','b')
       !
       mylevelid  = my_bgrp_id
       nlevel     = nbgrp
       level_comm = inter_bgrp_comm
       info       = 'b'
       !
    CASE('Z','z')
       !
       mylevelid  = me_bgrp
       nlevel     = nproc_bgrp
       level_comm = intra_bgrp_comm
       info       = 'z'
       !
    CASE DEFAULT
       !
       CALL errore('idistribute','Invalid level',1)
       !
    END SELECT
    !
    ! Generate nglob, nloc, nloc_min, nlocx
    !
    nglob    = n
    nloc     = n/nlevel
    nloc_min = nloc
    IF(MOD(n,nlevel) == 0) THEN
       nlocx = nloc
    ELSE
       nlocx = nloc+1
    ENDIF
    IF(mylevelid < MOD(n,nlevel)) THEN
       nloc = nloc+1
    ENDIF
    !
    ! Report the distribution across groups
    !
    IF(lverbose) THEN
       CALL io_push_title('Parallelization for '//TRIM(label))
       CALL io_push_value('nglob',nglob,20)
       CALL io_push_value('nlevel',nlevel,20)
       CALL io_push_value('Min nglob/nlevel',nloc_min,20)
       CALL io_push_value('Max nglob/nlevel',nlocx,20)
       CALL io_push_bar()
    ENDIF
    !
    ! Get myoffset
    !
    myoffset = mylevelid*(n/nlevel)
    IF(mylevelid < MOD(n,nlevel)) THEN
       myoffset = myoffset+mylevelid
    ELSE
       myoffset = myoffset+MOD(n,nlevel)
    ENDIF
    !
    this%nloc      = nloc
    this%nlocx     = nlocx
    this%nglob     = nglob
    this%myoffset  = myoffset
    this%nlevel    = nlevel
    this%mylevelid = mylevelid
    this%mpicomm   = level_comm
    this%info      = info
    !
    IF(PRESENT(scheme)) THEN
       IF(scheme /= IDIST_CYC .AND. scheme /= IDIST_BLK) THEN
          CALL errore('idistribute','Invalid distribution scheme',1)
       ENDIF
       this%scheme = scheme
    ELSE
       this%scheme = IDIST_CYC
    ENDIF
    !
  END SUBROUTINE
  !
  SUBROUTINE idistribute_g2l(this,iglob,iloc,who)
    !
    IMPLICIT NONE
    !
    ! I/O
    !
    CLASS(idistribute),INTENT(IN) :: this
    INTEGER,INTENT(IN) :: iglob
    INTEGER,INTENT(OUT) :: iloc,who
    !
    ! Workspace
    !
    INTEGER :: p,q
    !
    SELECT CASE(this%scheme)
    CASE(IDIST_CYC)
       !
       iloc = ((iglob-1)/this%nlevel)+1
       who  = MOD(iglob-1,this%nlevel)
       !
    CASE(IDIST_BLK)
       !
       p = this%nglob/this%nlevel
       q = MOD(this%nglob,this%nlevel)
       !
       IF(iglob <= (p+1)*q) THEN
          iloc = MOD(iglob-1,p+1)+1
          who  = (iglob-1)/(p+1)
       ELSE
          iloc = MOD(iglob-(p+1)*q-1,p)+1
          who  = ((iglob-(p+1)*q-1)/p)+q
       ENDIF
       !
    CASE DEFAULT
       !
       CALL errore('idistribute','Invalid distribution scheme',1)
       !
    END SELECT
    !
  END SUBROUTINE
  !
  FUNCTION idistribute_l2g(this,iloc,myid) RESULT(iglob)
    !
    IMPLICIT NONE
    !
    ! I/O
    !
    CLASS(idistribute),INTENT(IN) :: this
    INTEGER,INTENT(IN) :: iloc
    INTEGER,INTENT(IN),OPTIONAL :: myid
    INTEGER :: iglob
    !
    ! Workspace
    !
    INTEGER :: pid,p,q
    !
    IF(PRESENT(myid)) THEN
       pid = myid
    ELSE
       pid = this%mylevelid
    ENDIF
    !
    SELECT CASE(this%scheme)
    CASE(IDIST_CYC)
       !
       iglob = this%nlevel*(iloc-1)+pid+1
       !
    CASE(IDIST_BLK)
       !
       p = this%nglob/this%nlevel
       q = MOD(this%nglob,this%nlevel)
       !
       IF(pid < q) THEN
          iglob = (p+1)*pid+iloc
       ELSE
          iglob = p*pid+q+iloc
       ENDIF
       !
    CASE DEFAULT
       !
       CALL errore('idistribute','Invalid distribution scheme',1)
       !
    END SELECT
    !
  END FUNCTION
  !
  SUBROUTINE idistribute_copyto(this,dato_out)
    !
    IMPLICIT NONE
    !
    CLASS(idistribute),INTENT(IN) :: this
    CLASS(idistribute),INTENT(OUT) :: dato_out
    !
    dato_out%nloc      = this%nloc
    dato_out%nlocx     = this%nlocx
    dato_out%nglob     = this%nglob
    dato_out%scheme    = this%scheme
    dato_out%myoffset  = this%myoffset
    dato_out%nlevel    = this%nlevel
    dato_out%mylevelid = this%mylevelid
    dato_out%mpicomm   = this%mpicomm
    dato_out%info      = this%info
    !
  END SUBROUTINE
  !
END MODULE
