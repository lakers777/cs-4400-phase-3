
-- CS4400: Introduction to Database Systems: Monday, October 13, 2025
-- ER Management System Stored Procedures & Views Template [1]

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set session SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'er_hospital_management';
use er_hospital_management;

-- -------------------
-- Views
-- -------------------

-- [1] room_wise_view()
-- -----------------------------------------------------------------------------
/* This view provides an overview of patient room assignments, including the patients’ 
first and last names, room numbers, managing department names, assigned doctors' first and 
last names (through appointments), and nurses' first and last names (through room). 
It displays key relationships between patients, their assigned medical staff, and 
the departments overseeing their care. Note that there will be a row for each combination 
of assigned doctor and assigned nurse.*/
-- -----------------------------------------------------------------------------
create or replace view room_wise_view as
select pt.firstName, pt.lastName, r.roomNumber as room_number, d.longName as dept_name, ppp.firstName as doc_first_name, ppp.lastName as doc_last_name,  n.firstName as nurse_first_name, n.lastName as nurse_last_name
FROM person as pt
JOIN room as r
ON r.occupiedBy = pt.ssn
JOIN department as d
ON r.managingDept = d.deptID 
LEFT JOIN appointment as app
ON app.patientId = pt.ssn
LEFT JOIN appt_assignment as appt
ON appt.patientId = pt.ssn
LEFT JOIN person as ppp
ON ppp.ssn = appt.doctorId
LEFT JOIN room_assignment as rass
ON rass.roomNumber = r.roomNumber
LEFT JOIN person as n
ON n.ssn = rass.nurseId;

-- [2] symptoms_overview_view()
-- -----------------------------------------------------------------------------
/* This view provides a comprehensive overview of patient appointments
along with recorded symptoms. Each row displays the patient’s SSN, their full name 
(HINT: the CONCAT function can be useful here), the appointment time, appointment date, 
and a list of symptoms recorded during the appointment with each symptom separated by a 
comma and a space (HINT: the GROUP_CONCAT function can be useful here). */
-- -----------------------------------------------------------------------------
create or replace view symptoms_overview_view as
select a.patientId, concat(ps.firstName,' ',ps.lastName)
, a.apptTime, a.apptDate
, group_concat(s.symptomType separator ', ')
from appointment as a left join person as ps on a.patientId = ps.ssn                #get full name, ssn, date, and time
cross join symptom as s on a.apptTime = s.apptTime and a.apptDate = s.apptDate      #get symptoms
group by a.PatientId, a.apptDate, a.apptTime ;

-- karan
create or replace view symptoms_overview_view as
select a.patientId as ssn,
concat(per.firstName, per.lastName) as fullName,
a.apptDate as apptDate,
a.apptTime as apptTime,
group_concat(s.symptomType order by s.symptomType) as symptoms
from appointment a
join symptom s on s.patientId = a.patientId and s.apptDate  = a.apptDate and s.apptTime  = a.apptTime
join person per on per.ssn = a.patientId
group by a.patientId, per.firstName, per.lastName, a.apptDate, a.apptTime;

-- [3] medical_staff_view()
-- -----------------------------------------------------------------------------
/* This view displays information about medical staff. For every nurse and doctor, it displays
their ssn, their "staffType" being either "nurse" or "doctor", their "licenseInfo" being either
their licenseNumber or regExpiration, their "jobInfo" being either their shiftType or 
experience, a list of all departments they work in in alphabetical order separated by a
comma and a space (HINT: the GROUP_CONCAT function can be useful here), and their "numAssignments" 
being either the number of rooms they're assigned to or the number of appointments they're assigned to. */
-- -----------------------------------------------------------------------------
create or replace view medical_staff_view as
select
d.ssn as ssn,
'doctor' as staffType,
cast(d.licenseNumber as char(100)) as licenseInfo,
cast(d.experience    as char(100)) as jobInfo,
ifnull(group_concat(distinct dept.longName order by dept.longName separator ', '), '') as departments,
count(distinct concat(aa.patientId, aa.apptDate, aa.apptTime)) as numAssignments
from doctor d
left join works_in wi on wi.staffSsn = d.ssn
left join department dept on dept.deptId = wi.deptId
left join appt_assignment aa on aa.doctorId = d.ssn
group by d.ssn, d.licenseNumber, d.experience
union all

select
n.ssn as ssn,
'nurse' as staffType,
cast(n.regExpiration as char(100)) as licenseInfo,
cast(n.shiftType    as char(100)) as jobInfo,
ifnull(group_concat(distinct dept.longName order by dept.longName separator ', '), '') as departments,
count(distinct ra.roomNumber) as numAssignments
from nurse n
left join works_in wi on wi.staffSsn = n.ssn
left join department dept on dept.deptId = wi.deptId
left join room_assignment ra on ra.nurseId = n.ssn
group by n.ssn, n.regExpiration, n.shiftType;

-- [4] department_view()
-- -----------------------------------------------------------------------------
/* This view displays information about every department in the hospital. The information
displayed should be the department's long name, number of total staff members, the number of 
doctors in the department, and the number of nurses in the department. If a department does not 
have any doctors/nurses/staff members, ensure the output for those columns is zero, not null */
-- -----------------------------------------------------------------------------
create or replace view department_view as
select '_';

-- [5] outstanding_charges_view()
-- -----------------------------------------------------------------------------
/* This view displays the outstanding charges for the patients in the hospital. 
“Outstanding charges” is the sum of appointment costs and order costs. It also 
displays a patient’s first name, last name, SSN, funds, number of appointments, 
and number of orders. Ensure there are no null values if there are no charges, 
appointments, orders for a patient (HINT: the IFNULL or COALESCE functions can be 
useful here).  */
-- -----------------------------------------------------------------------------
create or replace view outstanding_charges_view as
select
per.firstName as firstName,
per.lastName as lastName,
p.ssn as ssn,
p.funds as funds,
ifnull(a.apptCharges, 0) + ifnull(b.orderCharges, 0) as outstandingCharges,
ifnull(a.numAppointments, 0) as numAppointments,
ifnull(b.numOrders, 0) as numOrders from patient p join person per on per.ssn = p.ssn
left join (select patientId, count(*) as numAppointments, sum(cost) as apptCharges from appointment group by patientId) a on a.patientId = p.ssn
left join (select patientId, count(*) as numOrders, sum(cost) as orderCharges from med_order group by patientId) b on b.patientId = p.ssn;


-- -------------------
-- Stored Procedures
-- -------------------

-- [6] add_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new patient. If the new patient does 
not exist in the person table, then add them prior to adding the patient. 
Ensure that all input parameters are non-null, and that a patient with the given 
SSN does not already exist. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_patient;
delimiter /​/
create procedure add_patient (
	in ip_ssn varchar(40),
    in ip_first_name varchar(100),
    in ip_last_name varchar(100),
    in ip_birthdate date,
    in ip_address varchar(200), 
    in ip_funds integer,
    in ip_contact char(12)
)
sp_main: begin
	if ip_ssn is NULL or ip_first_name is NULL or ip_last_name is NULL or ip_birthdate is NULL or ip_address is NULL or ip_funds is NULL or ip_contact is NULL then SELECT 'Null values in input parameters' as reason; leave sp_main; end if;
    if NOT EXISTS (SELECT 1 FROM person WHERE ssn =ip_ssn) THEN insert into person (ssn, firstName, lastName, birthdate, address) values (ip_ssn, ip_first_name, ip_last_name, ip_birthdate, ip_address);
    end if;
    insert into patient values (ip_ssn, ip_funds, ip_contact);
end /​/
delimiter ;

-- [7] record_symptom()
-- -----------------------------------------------------------------------------
/* This stored procedure records a new symptom for a patient. Ensure that all input 
parameters are non-null, and that the referenced appointment exists for the given 
patient, date, and time. Ensure that the same symptom is not already recorded for 
that exact appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists record_symptom;
delimiter /​/
create procedure record_symptom (
	in ip_patientId varchar(40),
    in ip_numDays int,
    in ip_apptDate date,
    in ip_apptTime time,
    in ip_symptomType varchar(100)
)
sp_main: begin
if ip_patientId IS NULL OR ip_numDays IS NULL OR ip_apptDate IS NULL OR ip_apptTime IS NULL OR ip_symptomType IS NULL  THEN SELECT 'Inputs are Null' as reason; leave sp_main;
end if;
if exists (SELECT 1 from symptom WHERE ip_apptTime=apptTime AND ip_apptDate=apptDate AND patientId=ip_patientId and symptomType = ip_symptomType) THEN SELECT 'Already exists' as reason; leave sp_main;
end if;
if NOT exists (SELECT 1 from appointment WHERE ip_apptTime=apptTime AND ip_apptDate=apptDate and patientId=ip_patientId) THEN SELECT 'Appointment doesnt exist' as reason; leave sp_main;
END IF;
insert into symptom values (ip_symptomType, ip_numDays, ip_patientId, ip_apptDate, ip_apptTime);
end /​/
delimiter ;

-- [8] book_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure books a new appointment for a patient at a specific time and date.
The appointment date/time must be in the future (the CURDATE() and CURTIME() functions will
be helpful). The patient must not have any conflicting appointments and must have the funds
to book it on top of any outstanding costs. Each call to this stored procedure must add the 
relevant data to the appointment table if conditions are met. Ensure that all input parameters 
are non-null and reference an existing patient, and that the cost provided is non‑negative. 
Do not charge the patient, but ensure that they have enough funds to cover their current outstanding 
charges and the cost of this appointment.
HINT: You should complete outstanding_charges_view before this procedure! */
-- -----------------------------------------------------------------------------
drop procedure if exists book_appointment;
delimiter /​/
create procedure book_appointment (
	in ip_patientId char(11),
	in ip_apptDate date,
    in ip_apptTime time,
	in ip_apptCost integer
)
sp_main: begin
	declare v_funds integer default 0;
    declare v_appt_sum integer default 0;
    declare v_order_sum integer default 0;
    declare v_needed integer default 0;
    if ip_patientId is null or ip_apptDate is null or ip_apptTime is null or ip_apptCost is null then leave sp_main;
    end if;
    if ip_apptCost < 0 then leave sp_main;
    end if;
    if not exists (select 1 from patient where ssn = ip_patientId) then leave sp_main;
    end if;
    if ip_apptDate < curdate() or (ip_apptDate = curdate() and ip_apptTime <= curtime()) then leave sp_main;
    end if;
    if exists (select 1 from appointment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime) then leave sp_main;
    end if;
    select funds into v_funds from patient where ssn = ip_patientId;
	select ifnull(sum(cost), 0) into v_appt_sum from appointment where patientId = ip_patientId;
	select ifnull(sum(cost), 0) into v_order_sum from med_order where patientId = ip_patientId;
    set v_needed = v_appt_sum + v_order_sum + ip_apptCost;
    if v_funds < v_needed then leave sp_main;
    end if;
    insert into appointment (patientId, apptDate, apptTime, cost)
    values (ip_patientId, ip_apptDate, ip_apptTime, ip_apptCost);
end /​/
delimiter ;

-- [9] place_order()
-- -----------------------------------------------------------------------------
/* This stored procedures places a new order for a patient as ordered by their
doctor. The patient must also have enough funds to cover the cost of the order on 
top of any outstanding costs. Each call to this stored procedure will represent 
either a prescription or a lab report, and the relevant data should be added to the 
corresponding table. Ensure that the order-specific, patient-specific, and doctor-specific 
input parameters are non-null, and that either all the labwork specific input parameters are 
non-null OR all the prescription-specific input parameters are non-null (i.e. if ip_labType 
is non-null, ip_drug and ip_dosage should both be null).
Ensure the inputs reference an existing patient and doctor. 
Ensure that the order number is unique for all orders and positive. Ensure that a cost 
is provided and non‑negative. Do not charge the patient, but ensure that they have 
enough funds to cover their current outstanding charges and the cost of this appointment. 
Ensure that the priority is within the valid range. If the order is a prescription, ensure 
the dosage is positive. Ensure that the order is never recorded as both a lab work and a prescription.
The order date inserted should be the current date, and the previous procedure lists a function that
will be required to use in this procedure as well.
HINT: You should complete outstanding_charges_view before this procedure! */
-- -----------------------------------------------------------------------------
drop procedure if exists place_order;
delimiter /​/
create procedure place_order (
	in ip_orderNumber int, 
	in ip_priority int,
    in ip_patientId char(11), 
	in ip_doctorId char(11),
    in ip_cost integer,
    in ip_labType varchar(100),
    in ip_drug varchar(100),
    in ip_dosage int
)
sp_main: begin
	declare v_funds integer default 0;
    declare v_appt_sum integer default 0;
    declare v_order_sum integer default 0;
    declare v_needed integer default 0;
    declare v_is_lab integer default 0;
    declare v_is_rx integer default 0;
    if ip_orderNumber is null or ip_priority is null or ip_patientId is null or ip_doctorId is null or ip_cost is null then leave sp_main;
    end if;
    if ip_orderNumber <= 0 or ip_cost < 0 then leave sp_main;
    end if;
    if exists (select 1 from med_order where orderNumber = ip_orderNumber) then leave sp_main;
    end if;
    if not exists (select 1 from patient where ssn = ip_patientId) then leave sp_main;
    end if;
    if not exists (select 1 from doctor where ssn = ip_doctorId) then leave sp_main;
    end if;
    set v_is_lab = case when ip_labType is not null and ip_drug is null and ip_dosage is null then 1 else 0 
	end;
    set v_is_rx  = case when ip_labType is null and ip_drug is not null and ip_dosage is not null then 1 else 0
	end;
    if v_is_lab + v_is_rx <> 1 then leave sp_main;
    end if;
    if v_is_rx = 1 and ip_dosage <= 0 then leave sp_main;
    end if;
    select funds into v_funds from patient where ssn = ip_patientId;
    select ifnull(sum(cost), 0) into v_appt_sum from appointment where patientId = ip_patientId;
    select ifnull(sum(cost), 0) into v_order_sum from med_order where patientId = ip_patientId;
    set v_needed = v_appt_sum + v_order_sum + ip_cost;
    if v_funds < v_needed then leave sp_main;
    end if;
    insert into med_order (orderNumber, orderDate, priority, patientId, doctorId, cost)
    values (ip_orderNumber, curdate(), ip_priority, ip_patientId, ip_doctorId, ip_cost);
    if v_is_lab = 1 then insert into lab_work (orderNumber, labType) values (ip_orderNumber, ip_labType);
    else insert into prescription (orderNumber, drug, dosage) values (ip_orderNumber, ip_drug, ip_dosage);
    end if;
end /​/
delimiter ;

-- [10] add_staff_to_dept()
-- -----------------------------------------------------------------------------
/* This stored procedure adds a staff member to a department. If they are already
a staff member and not a manager for a different department, they can be assigned
to this new department. If they are not yet a staff member or person, they can be 
assigned to this new department and all other necessary information should be 
added to the database. Ensure that all input parameters are non-null and that the 
Department ID references an existing department. Ensure that the staff member is 
not already assigned to the department. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_staff_to_dept;
delimiter /​/
create procedure add_staff_to_dept (
	in ip_deptId integer,
    in ip_ssn char(11),
    in ip_firstName varchar(100),
	in ip_lastName varchar(100),
    in ip_birthdate date,
    in ip_startdate date,
    in ip_address varchar(200),
    in ip_staffId integer,
    in ip_salary integer
)
sp_main: begin
    if ip_deptId is null or ip_ssn is null or ip_firstName is null or ip_lastName is null or ip_birthdate is null or ip_startdate is null or ip_address is null or ip_staffId  is null or ip_salary is null then leave sp_main;
    end if;
    if not exists (select 1 from department where deptId = ip_deptId) then leave sp_main;
    end if;
    if exists (select 1 from department where manager = ip_ssn and deptId <> ip_deptId) then leave sp_main;
    end if;
    if not exists (select 1 from person where ssn = ip_ssn) then insert into person (ssn, firstName, lastName, birthdate, address) values (ip_ssn, ip_firstName, ip_lastName, ip_birthdate, ip_address);
    end if;
    if not exists (select 1 from staff where ssn = ip_ssn) then insert into staff (ssn, staffId, hireDate, salary) values (ip_ssn, ip_staffId, ip_startdate, ip_salary);
    end if;
    if exists (select 1 from works_in where staffSsn = ip_ssn and deptId   = ip_deptId) then leave sp_main;
    end if;
    insert into works_in (staffSsn, deptId)
    values (ip_ssn, ip_deptId);
end /​/
delimiter ;

-- [11] add_funds()
-- -----------------------------------------------------------------------------
/* This stored procedure adds funds to an existing patient. The amount of funds
added must be positive. Ensure that all input parameters are non-null and reference 
an existing patient. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_funds;
delimiter /​/
create procedure add_funds (
	in ip_ssn char(11),
    in ip_funds integer
)
sp_main: begin
if not exists (select 1 from patient where ssn =ip_ssn) THEN select 'Patient doesnt exist here'; leave sp_main;
END IF;
if ip_ssn IS NULL or ip_funds IS NULL THEn select 'Null values'; leave sp_main;
END if;
if ip_funds < 0 THEN SELECT 'funds are below 0'; leave sp_main;
end if;
update patient 
set funds = funds + ip_funds 
where ssn = ip_ssn;
end /​/
delimiter ;

-- [12] assign_nurse_to_room()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a nurse to a room. In order to ensure they
are not over-booked, a nurse cannot be assigned to more than 4 rooms. Ensure that 
all input parameters are non-null and reference an existing nurse and room. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_nurse_to_room;
delimiter /​/
create procedure assign_nurse_to_room (
	in ip_nurseId char(11),
    in ip_roomNumber integer
)
sp_main: begin
if ip_nurseId is NULL or ip_roomNumber is Null then select 'null values'; leave sp_main;
end if;
if not exists (select 1 from nurse where ssn = ip_nurseId) THEN select 'nurse dne'; leave sp_main;
end if;
if not exists (select 1 from room where roomNumber = ip_roomNumber) THEN select 'room dne'; leave sp_main;
end if;
if (select count(*) from room_assignment where nurseId = ip_nurseId) > 3 THEN select 'overbooked'; leave sp_main;
end if;
insert into room_assignment (nurseId, roomNumber) values (ip_nurseId, ip_roomNumber);
end /​/
delimiter ;

-- [13] assign_room_to_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a room to a patient. The room must currently be
unoccupied. If the patient is currently assigned to a different room, they should 
be removed from that room. To ensure that the patient is placed in the correct type 
of room, we must also confirm that the provided room type matches that of the 
provided room number. Ensure that all input parameters are non-null and reference 
an existing patient and room. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_room_to_patient;
delimiter /​/
create procedure assign_room_to_patient (
    in ip_ssn char(11),
    in ip_roomNumber int,
    in ip_roomType varchar(100)
)
sp_main: begin
    -- code here
end /​/
delimiter ;

-- [14] assign_doctor_to_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a doctor to an existing appointment. Ensure that no
more than 3 doctors are assigned to an appointment, and that the doctor does not
have commitments to other patients at the exact appointment time. Ensure that all input 
parameters are non-null and reference an existing doctor and appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_doctor_to_appointment;
delimiter /​/
create procedure assign_doctor_to_appointment (
	in ip_patientId char(11),
    in ip_apptDate date,
    in ip_apptTime time,
    in ip_doctorId char(11)
)
sp_main: begin
    declare v_count integer default 0;
    if ip_patientId is null or ip_apptDate is null or ip_apptTime is null or ip_doctorId is null then
    leave sp_main;
    end if;
    if not exists (select 1 from appointment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime) 
	then leave sp_main;
    end if;
    if not exists (select 1 from doctor where ssn = ip_doctorId) then leave sp_main;
    end if;
    if exists (select 1 from appt_assignment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime and doctorId = ip_doctorId) 
	then leave sp_main;
    end if;
    select count(*) into v_count
    from appt_assignment
    where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime;
    if v_count >= 3 then leave sp_main;
    end if;
    if exists (select 1 from appt_assignment aa where aa.doctorId = ip_doctorId and aa.apptDate = ip_apptDate and aa.apptTime = ip_apptTime) 
	then leave sp_main;
    end if;
    insert into appt_assignment (patientId, apptDate, apptTime, doctorId)
    values (ip_patientId, ip_apptDate, ip_apptTime, ip_doctorId);
end /​/
delimiter ;

-- [15] manage_department()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a staff member as the manager of a department.
The staff member cannot currently be the manager for any departments. They
should be removed from working in any departments except the given
department (make sure the staff member is not the sole employee for any of these 
other departments, as they cannot leave and be a manager for another department otherwise),
for which they should be set as its manager. Ensure that all input parameters are non-null 
and reference an existing staff member and department.
*/
-- -----------------------------------------------------------------------------
drop procedure if exists manage_department;
delimiter /​/
create procedure manage_department (
	in ip_ssn char(11),
    in ip_deptId int
)
sp_main: begin
if ip_ssn is NULL or ip_deptId is NULL then select 'null values' as reason; leave sp_main;
end if;
if not exists (select 1 from staff where ssn = ip_ssn) THEN select 'staff dne'; leave sp_main;
end if;
if not exists (select 1 from department where deptId = ip_deptId) THEN select 'dept dne'; leave sp_main;
end if;
if exists (select 1 from department where manager = ip_ssn) THEN select 'already managing somewhere' as reason; leave sp_main;
end if;
if exists (select 1 from works_in as workd where staffSsn = ip_ssn and deptId  != ip_deptId and (select count(*) from works_in as workp where workd.deptId =workp.deptId) = 1) then select 'he/she cant leave, only emp'; leave sp_main;
end if;
delete from works_in
where staffSsn = ip_ssn and deptId!=ip_deptId;
if not exists (select 1 from works_in where works_in.staffSsn = ip_ssn and works_in.deptId = ip_deptId) then insert into works_in (staffSsn, deptId) values (ip_ssn, ip_deptId);
end if;
update department
set manager = ip_ssn 
where deptId = ip_deptId;

end /​/
delimiter ;

-- [16] release_room()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a patient from a given room. Ensure that 
the input room number is non-null and references an existing room.  */
-- -----------------------------------------------------------------------------
drop procedure if exists release_room;
delimiter /​/
create procedure release_room (
    in ip_roomNumber int
)
sp_main: begin
if ip_roomNumber is NULL then select 'Null Value' as reason; leave sp_main;
end if;
if not exists (select 1 from room where roomNumber = ip_roomNumber) THEN select 'room dne'; leave sp_main;
end if;
-- if exists (select 1 from room as r join patient as p where r.occupiedBy = p.ssn) THEN delete from room where ip_roomNumber = roomNumber; leave sp_main;
update room  set occupiedBy = NULL where roomNumber = ip_roomNumber; leave sp_main;
end /​/
delimiter ;

-- [17] remove_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a given patient. If the patient has any pending
orders or remaining appointments (regardless of time), they cannot be removed.
If the patient is not a staff member, they then must be completely removed from 
the database. Ensure all data relevant to this patient is removed. Ensure that the 
input SSN is non-null and references an existing patient. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_patient;
delimiter /​/
create procedure remove_patient (
	in ip_ssn char(11)
)
sp_main: begin
if ip_ssn IS NULL then select 'Null value' as reason; leave sp_main;
end if;
if NOT exists (select 1 from patient where ssn = ip_ssn) THEN select 'Patient dne' as reason; leave sp_main;
end if;
if exists (select 1 from appointment where patientId = ip_ssn AND apptDate > curdate()) THEN select 'patient has future appt'; leave sp_main;
end if;
if exists (select 1 from med_order where patientId = ip_ssn AND orderDate > curdate()) THEN select 'patient has med orders pending'; leave sp_main;
end if;
if NOT exists (select 1 from staff where staff.ssn = ip_ssn) THEN delete from person where ssn = ip_ssn; leave sp_main;
end if;
end /​/
delimiter ;

-- remove_staff()
-- Lucky you, we provided this stored procedure to you because it was more complex
-- than we would expect you to implement. You will need to call this procedure
-- in the next procedure!
-- -----------------------------------------------------------------------------
/* This stored procedure removes a given staff member. If the staff member is a 
manager, they are not removed. If the staff member is a nurse, all rooms
they are assigned to have a remaining nurse if they are to be removed. 
If the staff member is a doctor, all appointments they are assigned to have
a remaining doctor and they have no pending orders if they are to be removed.
If the staff member is not a patient, then they are completely removed from 
the database. All data relevant to this staff member is removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_staff;
delimiter /​/
create procedure remove_staff (
	in ip_ssn char(11)
)
sp_main: begin
	-- ensure parameters are not null
    if ip_ssn is null then
		leave sp_main;
	end if;
    
	-- ensure staff member exists
	if not exists (select ssn from staff where ssn = ip_ssn) then
		leave sp_main;
	end if;
	
    -- if staff member is a nurse
    if exists (select ssn from nurse where ssn = ip_ssn) then
	if exists (
		select 1
		from (
			 -- Get all rooms assigned to the nurse
			 select roomNumber
			 from room_assignment
			 where nurseId = ip_ssn
		) as my_rooms
		where not exists (
			 -- Check if there is any other nurse assigned to that room
			 select 1
			 from room_assignment 
			 where roomNumber = my_rooms.roomNumber
			   and nurseId <> ip_ssn
		)
	)
	then
		leave sp_main;
	end if;
		
        -- remove this nurse from room_assignment and nurse tables
		delete from room_assignment where nurseId = ip_ssn;
		delete from nurse where ssn = ip_ssn;
	end if;
	
    -- if staff member is a doctor
	if exists (select ssn from doctor where ssn = ip_ssn) then
		-- ensure the doctor does not have any pending orders
		if exists (select * from med_order where doctorId = ip_ssn) then 
			leave sp_main;
		end if;
		
		-- ensure all appointments assigned to this doctor have remaining doctors assigned
		if exists (
		select 1
		from (
			 -- Get all appointments assigned to ip_ssn
			 select patientId, apptDate, apptTime
			 from appt_assignment
			 where doctorId = ip_ssn
		) as ip_appointments
		where not exists (
			 -- For the same appointment, check if there is any other doctor assigned
			 select 1
			 from appt_assignment 
			 where patientId = ip_appointments.patientId
			   and apptDate = ip_appointments.apptDate
			   and apptTime = ip_appointments.apptTime
			   and doctorId <> ip_ssn
		)
	)
	then
		leave sp_main;
	end if;
        
		-- remove this doctor from appt_assignment and doctor tables
		delete from appt_assignment where doctorId = ip_ssn;
		delete from doctor where ssn = ip_ssn;
	end if;
    
    -- remove staff member from works_in and staff tables
    delete from works_in where staffSsn = ip_ssn;
    delete from staff where ssn = ip_ssn;

	-- ensure staff member is not a patient
	if exists (select * from patient where ssn = ip_ssn) then 
		leave sp_main;
	end if;
    
    -- remove staff member from person table
	delete from person where ssn = ip_ssn;
end /​/
delimiter ;

-- [18] remove_staff_from_dept()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a staff member from a department. If the staff
member is the manager of that department, they cannot be removed. If the staff
member, after removal, is no longer working for any departments, they should then 
also be removed as a staff member, following all logic in the remove_staff procedure. 
Ensure that all input parameters are non-null and that the given person works for
the given department. Ensure that the department will have at least one staff member 
remaining after this staff member is removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_staff_from_dept;
delimiter /​/
create procedure remove_staff_from_dept (
	in ip_ssn char(11),
    in ip_deptId integer
)
sp_main: begin
	-- code here
end /​/
delimiter ;

-- [19] complete_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure completes an appointment given its date, time, and patient SSN.
The completed appointment and any related information should be removed 
from the system, and the patient should be charged accordingly. Ensure that all 
input parameters are non-null and that they reference an existing appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists complete_appointment;
delimiter /​/
create procedure complete_appointment (
	in ip_patientId char(11),
    in ip_apptDate DATE, 
    in ip_apptTime TIME
)
sp_main: begin
	-- code here
end /​/
delimiter ;

-- [20] complete_orders()
-- -----------------------------------------------------------------------------
/* This stored procedure attempts to complete a certain number of orders based on the 
passed in value. Orders should be completed in order of their priority, from highest to
lowest. If multiple orders have the same priority, the older dated one should be 
completed first. Any completed orders should be removed from the system, and patients 
should be charged accordingly. Ensure that there is a non-null number of orders
passed in, and complete as many as possible up to that limit. */
-- -----------------------------------------------------------------------------
drop procedure if exists complete_orders;
delimiter /​/
create procedure complete_orders (
	in ip_num_orders integer
)
sp_main: begin
	-- code here
end /​/
delimiter ;
