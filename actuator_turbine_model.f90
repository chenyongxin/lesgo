!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Written by: 
!!
!!   Luis 'Tony' Martinez <tony.mtos@gmail.com> (Johns Hopkins University)
!!
!!   Copyright (C) 2012-2013, Johns Hopkins University
!!
!!   This file is part of The Actuator Turbine Model Library.
!!
!!   The Actuator Turbine Model is free software: you can redistribute it 
!!   and/or modify it under the terms of the GNU General Public License as 
!!   published by the Free Software Foundation, either version 3 of the 
!!   License, or (at your option) any later version.
!!
!!   The Actuator Turbine Model is distributed in the hope that it will be 
!!   useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
!!   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!   GNU General Public License for more details.
!!
!!   You should have received a copy of the GNU General Public License
!!   along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!*******************************************************************************
module actuator_turbine_model
!*******************************************************************************
! This module has the subroutines to provide all calculations for use in the 
! actuator turbine model (ATM)

! Imported modules
use atm_base ! Include basic types and precission of real numbers

use atm_input_util ! Utilities to read input files

implicit none

! Declare everything private except for subroutine which will be used
private 
public :: atm_initialize, atm_forcing, numberOfTurbines,                    &
          atm_computeBladeForce, atm_update,                                &
          vector_add, vector_divide, vector_mag, distance

! These are used to do unit conversions
real(rprec), parameter :: pi= 3.141592653589793238462643383279502884197169399375
real(rprec) :: degRad = pi/180. ! Degrees to radians conversion
real(rprec) :: rpmRadSec =  pi/30. ! Set the revolutions/min to radians/s 

integer :: i, j, k ! Counters

logical :: pastFirstTimeStep ! Establishes if we are at the first time step

! Pointers to be used from the turbineArray and Turbinemodel modules
! It is very important to have the pointers pointing into the right variable
! in each subroutine
type(real(rprec)),  pointer :: db(:)
type(real(rprec)),  pointer :: bladePoints(:,:,:,:)
type(real(rprec)),  pointer :: bladeRadius(:,:,:)
real(rprec), pointer :: bladeAlignedVectors(:,:,:,:,:)
real(rprec), pointer :: cl(:,:,:), cd(:,:,:), alpha(:,:,:), twistAng(:,:,:)
real(rprec), pointer :: windVectors(:,:,:,:)
integer,     pointer :: numBladePoints
integer,     pointer :: numBl
integer,     pointer :: numAnnulusSections
integer,     pointer :: numSec     
integer,     pointer :: turbineTypeID
real(rprec), pointer :: NacYaw             
real(rprec), pointer :: azimuth
real(rprec), pointer :: rotSpeed
real(rprec), pointer :: ShftTilt
real(rprec), pointer :: towerShaftIntersect(:)
real(rprec), pointer :: baseLocation(:)
real(rprec), pointer :: rotorApex(:)
real(rprec), pointer :: uvShaft(:)
real(rprec), pointer :: uvTower(:)
real(rprec), pointer :: TowerHt
real(rprec), pointer :: Twr2Shft
real(rprec), pointer :: OverHang
real(rprec), pointer :: UndSling
real(rprec), pointer :: uvShaftDir
real(rprec), pointer :: TipRad
real(rprec), pointer :: HubRad
real(rprec), pointer :: PreCone
real(rprec), pointer :: projectionRadius  ! Radius up to which forces are spread
real(rprec), pointer :: sphereRadius ! Radius of the sphere of forces 
real(rprec), pointer :: chord  

! Subroutines for the actuator turbine model 
! All suboroutines names start with (atm_) 
contains 
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_initialize()
! This subroutine initializes the ATM. It calls the subroutines in
! atm_input_util to read the input data and creates the initial geometry
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
implicit none
pastFirstTimeStep=.false. ! The first time step not reached yet

call read_input_conf()  ! Read input data

do i = 1,numberOfTurbines
    call atm_create_points(i)   ! Creates the ATM points defining the geometry
    call atm_calculate_variables(i) ! Calculates variables depending on input
end do
pastFirstTimeStep=.true. ! Past the first time step

end subroutine atm_initialize


!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_update(dt)
! This subroutine updates the model each time-step
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
integer :: i
real(rprec) :: dt                            ! Time step

do i = 1, numberOfTurbines
    call atm_rotateBlades(dt,i)              ! Rotate the blades of each turbine
end do

end subroutine atm_update


!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_rotateBlades(dt,i)
! This subroutine rotates the turbine blades 
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
integer :: i                                 ! Turbine number
integer :: j                                 ! Turbine type
integer :: k, n, m                           ! Counters tu be used in do loops
real(rprec) :: dt                            ! time step
real(rprec) :: deltaAzimuth, deltaAzimuthI   ! Angle of rotation


! Variables which are used by pointers
rotorApex=> turbineArray(i) % rotorApex
j=turbineArray(i) % turbineTypeID
rotSpeed=>turbineArray(i) % rotSpeed
uvShaft=>turbineArray(i) % uvShaft
azimuth=>turbineArray(i) % azimuth

! Angle of rotation
deltaAzimuth = rotSpeed * dt;

! Check the rotation direction first and set the local delta azimuth
! variable accordingly.
if (turbineArray(i) % rotationDir == "cw") then
    deltaAzimuthI = deltaAzimuth
else if (turbineArray(i) % rotationDir == "ccw") then
    deltaAzimuthI =-deltaAzimuth
end if

do m=1, turbineArray(i) % numAnnulusSections
    do n=1, turbineArray(i) % numBladePoints
        do k=1, turbineModel(j) % numBl
            turbineArray(i) %   bladePoints(k,n,m,:)=rotatePoint(              &
            turbineArray(i) % bladePoints(k,n,m,:), rotorApex, uvShaft,        &
            deltaAzimuthI)
        enddo
    enddo
enddo

if (pastFirstTimeStep) then
    azimuth = azimuth + deltaAzimuth;
        if (azimuth .ge. 2.0 * pi) then
            azimuth =azimuth - 2.0 *pi;
        endif
endif
    
end subroutine atm_rotateBlades


!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_create_points(i)
! This subroutine generate the set of blade points for each turbine
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
integer, intent(in) :: i ! Indicates the turbine number
integer :: j ! Indicates the turbine type
integer :: m ! Indicates the blade point number
real(rprec), dimension (3) :: root ! Location of rotor apex
real(rprec) :: beta ! Difference between coning angle and shaft tilt
real(rprec) :: dist ! Distance from each actuator point
! Width of the actuator section

! Identifies the turbineModel being used
j=turbineArray(i) % turbineTypeID ! The type of turbine (eg. NREL5MW)

! Variables to be used locally. They are stored in local variables within the 
! subroutine for easier code following. The values are then passed to the 
! proper type
numBladePoints => turbineArray(i) % numBladePoints
numBl=>turbineModel(j) % numBl
numAnnulusSections=>turbineArray(i) % numAnnulusSections


nacYaw=>turbineArray(i) % nacYaw

! Allocate variables depending on specific turbine properties and general
! turbine model properties
allocate(turbineArray(i) % db(numBladePoints))

allocate(turbineArray(i) % bladePoints(numBl, numAnnulusSections, &
         numBladePoints,3))
         
allocate(turbineArray(i) % bladeRadius(numBl,numAnnulusSections,numBladePoints))  

! Assign Pointers
db=>turbineArray(i) % db
bladePoints=>turbineArray(i) % bladePoints
bladeRadius=>turbineArray(i) % bladeRadius
azimuth=>turbineArray(i) % azimuth
rotSpeed=>turbineArray(i) % rotSpeed
ShftTilt=>turbineModel(j) % ShftTilt
preCone=>turbineModel(j) % preCone
towerShaftIntersect=>turbineArray(i) % towerShaftIntersect
baseLocation=>turbineArray(i) % baseLocation
TowerHt=>turbineModel(j) % TowerHt
Twr2Shft=> turbineModel(j) % Twr2Shft
rotorApex=>turbineArray(i) % rotorApex
OverHang=>turbineModel(j) % OverHang
UndSling=>turbineModel(j) % UndSling
uvShaftDir=>turbineArray(i) % uvShaftDir
uvShaft=>turbineArray(i) % uvShaft
uvTower=>turbineArray(i) % uvTower
TipRad=>turbineModel(j) % TipRad
HubRad=>turbineModel(j) % HubRad
PreCone=>turbineModel(j) %PreCone

!!-- Do all proper conversions for the required variables
! Convert nacelle yaw from compass directions to the standard convention
call compassToStandard(nacYaw)
! Turbine specific
azimuth = degRad*(azimuth)
rotSpeed = rpmRadSec * rotSpeed
nacYaw =degRad * nacYaw
! Turbine model specific
shftTilt = degRad *  shftTilt 
preCone =degRad * preCone

! Calculate tower shaft intersection and rotor apex locations. (The i-index is 
! at the turbine array level for each turbine and the j-index is for each type 
! of turbine--if all turbines are the same, j- is always 0.)  The rotor apex is
! not yet rotated for initial yaw that is done below.
towerShaftIntersect = turbineArray(i) % baseLocation
towerShaftIntersect(3) = towerShaftIntersect(3) + TowerHt + Twr2Shft
rotorApex = towerShaftIntersect
rotorApex(1) = rotorApex(1) +  (OverHang + UndSling) * cos(ShftTilt)
rotorApex(3) = rotorApex(3) +  (OverHang + UndSling) * sin(ShftTilt)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!                  Create the first set of actuator points                     !
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! Define the vector along the shaft pointing in the direction of the wind
uvShaftDir = OverHang / abs( OverHang )
! Define the vector along the shaft pointing in the direction of the wind                               
uvShaft = vector_add(rotorApex , - towerShaftIntersect)
uvShaft = vector_divide(uvShaft, vector_mag(uvShaft))
! Define vector aligned with the tower pointing from the ground to the nacelle
uvTower = vector_add(towerShaftIntersect, - baseLocation)
uvTower = vector_divide( uvTower, vector_mag(uvTower))
! Define thickness of each blade section
do k=1, numBladePoints
    db(k) = (TipRad- HubRad)/(numBladePoints)
enddo

root = rotorApex
beta = PreCone - ShftTilt

! This creates the first set of points
do k=1, numBl
    root(1)= root(1) + HubRad*sin(beta)
    root(3)= root(3) + HubRad*cos(beta)
    dist = HubRad
    do m=1, numBladePoints
        dist = dist + 0.5*(db(k))
        bladePoints(k,1,m,1) = root(1) + dist*sin(beta)
        bladePoints(k,1,m,2) = root(2)
        bladePoints(k,1,m,3) = root(3) + dist*cos(beta);
        bladeRadius(k,1,m) = dist;
        dist = dist + 0.5*(db(k))
    enddo
    if (k > 1) then
        do m=1, numBladePoints
            bladePoints(k,1,m,:)=rotatePoint(bladePoints(k,1,m,:), rotorApex, &
            uvShaft,(360.0/NumBl)*k*degRad)
        enddo
    endif
    
enddo


end subroutine atm_create_points

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_calculate_variables(i)
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! Calculates the variables of the model that need information from the input
! files. It runs after reading input information.
integer, intent(in) :: i ! Indicates the turbine number
integer :: j ! Indicates the turbine type

! Identifies the turbineModel being used
j=turbineArray(i) % turbineTypeID ! The type of turbine (eg. NREL5MW)

! Declare the required pointers
OverHang=>turbineModel(j) % OverHang
UndSling=>turbineModel(j) % UndSling
projectionRadius=>turbineArray(i) % projectionRadius
sphereRadius=>turbineArray(i) % sphereRadius
TipRad=>turbineModel(j) % TipRad
PreCone=>turbineModel(j) %PreCone

! First compute the radius of the force projection (to the radius where the 
! projection is only 0.0001 its maximum value - this seems to recover 99.99% of 
! the total forces when integrated
projectionRadius= turbineArray(i) % epsilon * sqrt(log(1.0/0.0001))

sphereRadius=sqrt(((OverHang + UndSling) + TipRad*sin(PreCone))**2 &
+ (TipRad*cos(PreCone))**2) + projectionRadius

end subroutine atm_calculate_variables

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_forcing()
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

end subroutine atm_forcing

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_computeBladeForce(i,m,n,q,U_local)
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! This subroutine will compute the wind vectors by projecting the velocity 
! onto the transformed coordinates system
integer, intent(in) :: i,m,n,q
! i - turbineTypeArray
! m - numAnnulusSections
! n - numBladePoints
! q - numBl
real(rprec), intent(in) :: U_local(3)    ! The local velocity at this point

! Local variables
integer :: j,k ! Use to identify turbine type (j) and length of airoilTypes (k)
integer :: sectionType_i ! The type of airfoil
real(rprec) :: cl_i, cd_i, twistAng_i, chord_i, Vmag_i, windAng_i, alpha_i, db_i
real(rprec), dimension(3) :: dragVector, liftVector


rotorApex => turbineArray(i) % rotorApex
bladeAlignedVectors => turbineArray(i) % bladeAlignedVectors
windVectors => turbineArray(i) % windVectors
bladePoints => turbineArray(i) % bladePoints
rotSpeed => turbineArray(i) % rotSpeed

! Pointers for blade properties
turbineTypeID => turbineArray(i) % turbineTypeID
NumSec => turbineModel(i) % NumSec
bladeRadius => turbineArray(i) % bladeRadius
!cd(m,n,q) => turbineArray(i) % cd(m,n,q)    ! Drag coefficient
!cl(m,n,q) => turbineArray(i) % cl(m,n,q)    ! Lift coefficient
!alpha(m,n,q) => turbineArray(i) % alpha(m,n,q) ! Anlge of attack

PreCone => turbineModel(i) % PreCone

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! This will compute the vectors defining the local coordinate 
! system of the actuator point
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! Define vector in z'
! If clockwise rotating, this vector points along the blade toward the tip.
! If counter-clockwise rotating, this vector points along the blade towards 
! the root.
if (turbineArray(i) % rotationDir == "cw")  then
    bladeAlignedVectors(m,n,q,2,:) =      &
                                     vector_add(bladePoints(m,n,q,:),-rotorApex)
elseif (turbineArray(i) % rotationDir == "ccw") then
    bladeAlignedVectors(m,n,q,3,:) =      &
                                     vector_add(-bladePoints(m,n,q,:),rotorApex)
endif
bladeAlignedVectors(m,n,q,3,:) =  &
                        vector_divide(bladeAlignedVectors(m,n,q,2,:),   &
                        vector_mag(bladeAlignedVectors(m,n,q,2,:)) )

! Define vector in y'
bladeAlignedVectors(m,n,q,2,:) = cross_product(bladeAlignedVectors(m,n,q,2,:), &
                                 turbineArray(i) % uvShaft)
bladeAlignedVectors(m,n,q,2,:) = vector_divide(bladeAlignedVectors(m,n,q,1,:), &
                                 vector_mag(bladeAlignedVectors(m,n,q,1,:)))

! Define vector in x'
bladeAlignedVectors(m,n,q,1,:) = cross_product(bladeAlignedVectors(m,n,q,2,:), &
                                 bladeAlignedVectors(m,n,q,3,:))
bladeAlignedVectors(m,n,q,1,:) = vector_divide(bladeAlignedVectors(m,n,q,1,:), &
                                 vector_mag(bladeAlignedVectors(m,n,q,1,:)))
! This concludes the definition of the local corrdinate system
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Now put the velocity in that cell into blade-oriented coordinates and add on 
! the velocity due to blade rotation.
windVectors(m,n,q,1) = dot_product(bladeAlignedVectors(m,n,q,1,:) , U_local)
windVectors(m,n,q,2) = dot_product(bladeAlignedVectors(m,n,q,2,:), U_local) + &
                      (rotSpeed * bladeRadius(m,n,q) * cos(PreCone));
windVectors(m,n,q,3) = dot_product(bladeAlignedVectors(m,n,q,3,:), U_local);

! Interpolate quantities through section
twistAng_i = interpolate(bladeRadius(m,n,q),                                   &
                       turbineModel(i) % radius(1:turbineModel(i) % NumSec),   &
                       turbineModel(i) % twist(1:turbineModel(i) % NumSec) )   
chord_i = interpolate(bladeRadius(m,n,q),                                      &
                       turbineModel(i) % radius(1:turbineModel(i) % NumSec),   &
                       turbineModel(i) % chord(1:turbineModel(i) % NumSec) )!
sectionType_i = interpolate_i(bladeRadius(m,n,q),                              &
                       turbineModel(i) % radius(1:turbineModel(i) % NumSec),   &
                       turbineModel(i) % sectionType(1:turbineModel(i)% NumSec))
! Velocity magnitude
Vmag_i=sqrt( windVectors(m,n,q,1)**2+windVectors(m,n,q,2)**2 )

! Angle between wind vector components
windAng_i = atan2( windVectors(m,n,q,1), windVectors(m,n,q,2) ) /degRad

! Local angle of attack
alpha_i=windAng_i-twistAng_i - turbineArray(i) % Pitch

! Tital number of entries in lists of AOA, cl and cd
k=turbineModel(j) % airfoilType(sectionType_i) % n

! Lift coefficient
cl_i=interpolate(alpha_i,                                                      &
                 turbineModel(j) % airfoilType(sectionType_i) % AOA(1:k),        &
                 turbineModel(j) % airfoilType(sectionType_i) % cl(1:k) )

! Drag coefficient
cd_i=interpolate(alpha_i,                                                      &
                 turbineModel(j) % airfoilType(sectionType_i) % AOA(1:k),        &
                 turbineModel(j) % airfoilType(sectionType_i) % cd(1:k) )

db_i = turbineArray(i) % db(q) 
! Lift force
turbineArray(i) % lift(m,n,q) = 0.5 * cl_i * Vmag_i**2 * chord_i * db_i

! Drag force
turbineArray(i) % drag(m,n,q) = 0.5 * cd_i * Vmag_i**2 * chord_i * db_i

dragVector = bladeAlignedVectors(m,n,q,1,:)*windVectors(m,n,q,1) +  &
             bladeAlignedVectors(m,n,q,2,:)*windVectors(m,n,q,2)

dragVector = vector_divide(dragVector,vector_mag(dragVector) )

! Lift vector
liftVector = cross_product(dragVector,bladeAlignedVectors(m,n,q,3,:) )
liftVector = vector_divide(liftVector,vector_mag(liftVector))

liftVector = -turbineArray(i) % lift(m,n,q) * liftVector;
dragVector = -turbineArray(i) % drag(m,n,q) * dragVector;

turbineArray(i) % bladeForces(m,n,q,:) = vector_add(liftVector, dragVector)



end subroutine atm_computeBladeForce


!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_convoluteForce(i,m,n,q,dis,Force,bodyForce)
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! This subroutine will compute the wind vectors by projecting the velocity 
! onto the transformed coordinates system
integer, intent(in) :: i,m,n,q
! i - turbineTypeArray
! m - numAnnulusSections
! n - numBladePoints
! q - numBl
real(rprec), intent(in) :: dis
real(rprec), intent(in) :: Force(3)
real(rprec), intent(out) :: bodyForce(3)    ! The local velocity at this point

bodyForce = Force * exp(-sqrt(dis/turbineArray(i) % epsilon)) /      &
((turbineArray(i) % epsilon**3)*(pi**1.5));


end subroutine atm_convoluteForce

!-------------------------------------------------------------------------------
function interpolate(xp,x,y)
! This function interpolates xp from x and y 
!-------------------------------------------------------------------------------
real(rprec), dimension(:), intent(in) :: x,y
real(rprec), intent(in) ::  xp
real(rprec)  :: interpolate
integer :: i,p
p=size(x)
if (xp .eq. x(1)) then 
    interpolate=y(1)
else if ( xp .eq. x(p) ) then
    interpolate=y(p)
else 
    do i=2,p-1
        if (xp.ge.x(i) .and. xp .le. x(i+1)) then
            interpolate=y(i)+(y(i+1)-y(i))/(x(i+1)-x(i))*(x(p)-x(i))
        endif
    enddo
endif

return
end function interpolate

!-------------------------------------------------------------------------------
function interpolate_i(xp,x,y)
! This function interpolates xp from x and y 
!-------------------------------------------------------------------------------
real(rprec), dimension(:), intent(in) :: x
integer, dimension(:), intent(in) :: y
real(rprec), intent(in) ::  xp
integer  :: interpolate_i
integer :: i,p
p=size(x)
if (xp .eq. x(1)) then 
    interpolate_i=y(1)
else if ( xp .eq. x(p) ) then
    interpolate_i=y(p)
else 
    do i=2,p-1
        if (xp.ge.x(i) .and. xp .le. x(i+1)) then
            interpolate_i=int( real(y(i),rprec)+(y(i+1)-real(y(i),rprec)) /    &
                        (x(i+1)-x(i))*(x(p)-x(i)) + 0.5 )
        endif
    enddo
endif

return
end function interpolate_i

!-------------------------------------------------------------------------------
function vector_add(a,b)
! This function adds 2 vectors (arrays real(rprec), dimension(3))
!-------------------------------------------------------------------------------
real(rprec), dimension(3), intent(in) :: a,b
real(rprec), dimension(3) :: vector_add
vector_add(1)=a(1)+b(1)
vector_add(2)=a(2)+b(2)
vector_add(3)=a(3)+b(3)
return
end function vector_add

!-------------------------------------------------------------------------------
function vector_divide(a,b)
! This function divides one vector (array real(rprec), dimension(3) by a number)
!-------------------------------------------------------------------------------
real(rprec), dimension(3), intent(in) :: a
real(rprec), intent(in) :: b
real(rprec), dimension(3) :: vector_divide
vector_divide(1)=a(1)/b
vector_divide(2)=a(2)/b
vector_divide(3)=a(3)/b
return
end function vector_divide

!-------------------------------------------------------------------------------
function vector_mag(a)
! This function calculates the magnitude of a vector
!-------------------------------------------------------------------------------
real(rprec), dimension(3), intent(in) :: a
real(rprec) :: vector_mag
vector_mag=abs(sqrt(a(1)**2+a(2)**2+a(3)**2))
return
end function vector_mag

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine compassToStandard(dir)
! This function converts nacelle yaw from compass directions to the standard
! convention of 0 degrees on the + x axis with positive degrees
! in the counter-clockwise direction.
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
real(rprec), intent(inout) :: dir
dir = dir + 180.0
if (dir .ge. 360.0) then
    dir = dir - 360.0
endif
dir = 90.0 - dir
if (dir < 0.0) then
    dir = dir + 360.0
endif
return 
end subroutine compassToStandard

!-------------------------------------------------------------------------------
function rotatePoint(point, rotationPoint, axis, angle)
! This function performs rotation of a point with respect to an axis or rotation
! and a certain angle
!-------------------------------------------------------------------------------
real(rprec), dimension(3) :: point
real(rprec), dimension(3) :: rotationPoint
real(rprec), dimension(3) :: axis
real(rprec) :: angle
real(rprec), dimension(3,3) :: RM ! Rotation Matrix tensor
real(rprec), dimension(3) :: rotatePoint

RM(1,1) = sqrt(axis(1)) + (1.0 - sqrt(axis(1))) * cos(angle); 
RM(1,2) = axis(1) * axis(2) * (1.0 - cos(angle)) - axis(3) * sin(angle); 
RM(1,3) = axis(1) * axis(3) * (1.0 - cos(angle)) + axis(2) * sin(angle);
RM(2,1) = axis(1) * axis(2) * (1.0 - cos(angle)) + axis(3) * sin(angle); 
RM(2,2) = sqrt(axis(2)) + (1.0 - sqrt(axis(2))) * cos(angle);
RM(2,3) = axis(2) * axis(3) * (1.0 - cos(angle)) - axis(1) * sin(angle);
RM(3,1) = axis(1) * axis(3) * (1.0 - cos(angle)) - axis(2) * sin(angle);
RM(3,2) = axis(2) * axis(3) * (1.0 - cos(angle)) + axis(1) * sin(angle);
RM(3,3) = sqrt(axis(3)) + (1.0 - sqrt(axis(3))) * cos(angle);

! Rotation matrices make a rotation about the origin, so need to subtract 
! rotation point off the point to be rotated
point=vector_add(point,-rotationPoint)

! Perform rotation
rotatePoint(1)=RM(1,1)*point(1)+RM(1,2)*point(2)+RM(1,3)*point(3)
rotatePoint(2)=RM(2,1)*point(1)+RM(2,2)*point(2)+RM(2,3)*point(3)
rotatePoint(3)=RM(3,1)*point(1)+RM(3,2)*point(2)+RM(3,3)*point(3)

! Return the rotated point to its new location relative to the rotation point
rotatePoint=rotatePoint+rotationPoint

return 
end function rotatePoint

!-------------------------------------------------------------------------------
function cross_product(a,b)
! This function calculates the magnitude of a vector
!-------------------------------------------------------------------------------
real(rprec), dimension(3), intent(in) :: a,b
real(rprec), dimension(3) :: cross_product
cross_product(1)=-a(3)*b(2)+a(3)*b(3)
cross_product(2)=a(3)*b(1)-a(1)*b(3)
cross_product(3)=-a(2)*b(1)+a(1)*b(2)
return
end function cross_product

!-------------------------------------------------------------------------------
function distance(a,b)
! This function calculates the distance between (a,b,c) and (d,e,f)
!-------------------------------------------------------------------------------
real(rprec), dimension(3), intent(in) :: a,b
real(rprec) :: distance
distance=sqrt((a(1)-b(1))**2+(a(2)-b(2))**2+(a(3)-b(3))**2)
return
end function distance


end module actuator_turbine_model

















