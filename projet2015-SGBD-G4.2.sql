-------(i)
--select * from user_tab_columns where table_name = upper('nom_table');  
set serveroutput on;
show errors;


-------------------------------------------------------
--*********************Q1****************************--
-------------------------------------------------------
--------(a)----------
--les positions des arrets dans le troncon doivent etre incrementes 1 quand executer apres insert on tableau stop_times.
------------------------
drop trigger AssurerIncremente;
create or replace trigger AssurerIncremente 
before insert  
on stop_times
for each row
declare			
	vSequnce number;
begin
	select max(STOP_SEQUENCE) into vSequnce from stop_times
		where TRIP_ID=:new.TRIP_ID;
	if(vSequnce+1 != :new.STOP_SEQUENCE) then raise_application_error(-20001,'stop_sequence ne doit pas y avoir de saut superieur a 1');
	end if;		
end;
/
--TEST
insert into stop_times values (4503603927916039,1970324837186202,28,'07:27:00','07:28:00');
insert into stop_times values (4503603927916039,1970324837186202,20,'07:27:00','07:28:00');
insert into stop_times values (4503603927916039,1970324837186202,27,'07:27:00','07:28:00');
delete from stop_times where STOP_SEQUENCE=27 and TRIP_ID=4503603927916039;
-------(b)---------
-- l’heure d’arrivee a un arret doit etre inferieure a l’heure de depart de ce meme arret.
-------------------
drop trigger AssurerArriInfeDepart;
create or replace trigger AssurerArriInfeDepart 
after insert or update 
on stop_times
declare
	cursor arriveInfeDepart is 
			select ARRIVAL_TIME,DEPARTURE_TIME from stop_times;	
begin
	for c_arriveInfeDepart in arriveInfeDepart loop
		if(TO_DATE(c_arriveInfeDepart.ARRIVAL_TIME,'HH24-MI-SS') >  TO_DATE(c_arriveInfeDepart.DEPARTURE_TIME,'HH24-MI-SS')) then 
			raise_application_error(-20002,'heure arrive inferieure a lheure de depart');
		end if;
	end loop;
end;
/

insert into stop_times values (4503603927916039,1970324837186202,27,'07:27:00','07:26:00');
	show errors;
l;
--------(c)------------
--la date de mise en service d’un service doit etre inferieure a la date de fin de service.
-----------------------
drop trigger AssurerCalendar;
create or replace trigger AssurerCalendar
after insert or update 
on calendar
declare
	cursor miseDateFin is
			select count(*) as serDateSupFinDate from calendar
			where start_date>end_date;
begin	
	for c_miseDateFin in miseDateFin loop		
		if(c_miseDateFin.serDateSupFinDate>0) then raise_application_error(-20003,'La date de mise en service de service doit etre inferieur a la date de fin de service');
		end if;
	end loop;
end;
/
--test
insert into calendar values (4785078899048782,0,0,0,0,0,0,0,'03-01-2014','03-01-2013');
------------(d)---------
--la date d’une exception d’un service doit etre comprise entre la date de debut de mise en service et la date de fin.
------------------------
drop trigger AssurerCalendarDatesException;
create or replace trigger AssurerCalendarDatesException
after insert or update
on calendar_dates
declare
	cursor dataBetween is 
		select count(*) as nbNotBetween from calendar c,calendar_dates cd
			where c.service_id=cd.service_id
				and cd.date_service not between c.start_date and c.end_date;
begin
	for c_dataBetween in dataBetween loop
		if(c_dataBetween.nbNotBetween>0) then raise_application_error(-20004,'La date nest pas entre la date de debut de mise en service et la date de fin');
		end if;
	end loop;
end;
/
--test
insert into calendar_dates values(4785078899048781,'03-01-2013',1)--EXCEPTION

insert into calendar_dates values(4785078899048781,'04-01-2014',1)
delete from calendar_dates where service_id=4785078899048781 and date_service='04-01-2014';
-------------(e)---------------
--il ne peut exister une station parent que si le type d’arret est egal a 0.
-------------------------------
drop trigger AssurerParentStation;
create or replace trigger AssurerParentStation 
after insert or update
on stops
for each row
declare
	
begin
	if(:new.parent_station > 0 and :new.location_type != 0) then  
		raise_application_error(-20005,'Il ne peut exister une station parent>0 que si le type darret est egal a 0 ');
	end if;
end;
/
-------------------------------------------------------
--*********************Q2****************************--
-------------------------------------------------------
--declarer une type row_type1 pour question 2-ii
CREATE OR REPLACE TYPE row_type AS OBJECT(tripsid VARCHAR2(50)); 
--declarer une table_type1 pour question 2-ii
create OR REPLACE type table_type as table of row_type;


drop package TravailFaire;
create or replace package TravailFaire
is
	procedure affichageTronLigne(vtrip_id Trips.trip_id%type);	
	function tronconsPrivee return table_type pipelined;
	procedure affichageHoraire;
	function calculeDuTemps (tripid trips.trip_id%type,arrive stops.stop_id%type,depart stops.stop_id%type)return number;
	procedure partirArret(arrive stops.stop_id%type);
end TravailFaire;

create or replace package BODY TravailFaire
iS 
	procedure affichageTronLigne(vtrip_id Trips.trip_id%type) is
		cursor idTronCon is
			select * from Trips where trip_id=vtrip_id; 
		cursor arretStation(vtrip_id Trips.trip_id%type) is		
			select * from stop_times where trip_id=vtrip_id;
		compteur number;
		vNbStation number;	
		vStopName stops.stop_name%type;
	begin
		compteur := 0;	
		for c_idTronCon in idTronCon loop
			select count(*) into vNbStation from stop_times where trip_id=c_idTronCon.trip_id;
			DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------------------');
			DBMS_OUTPUT.PUT_LINE('Identifiant de troncon:'||c_idTronCon.trip_id||' Nom de troncon:'||c_idTronCon.trip_headsign);
			DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------------------');
			if(c_idTronCon.direction_id = 1) 
				then 
					DBMS_OUTPUT.PUT_LINE('Retour');
				else 
					DBMS_OUTPUT.PUT_LINE('Aller');
			end if;
			for c_arretStation in arretStation(c_idTronCon.trip_id) loop
			select stop_name into vStopName from stops where stop_id=c_arretStation.STOP_ID;
				case
					when compteur = 0 then DBMS_OUTPUT.PUT_LINE('Depart:'||vStopName||'('||c_arretStation.ARRIVAL_TIME||'-'||c_arretStation.DEPARTURE_TIME||')');
					when compteur = vNbStation-1 then DBMS_OUTPUT.PUT_LINE('Arrivee:'||vStopName||'('||c_arretStation.ARRIVAL_TIME||'-'||c_arretStation.DEPARTURE_TIME||')');
					ELSE DBMS_OUTPUT.PUT_LINE('Arret'||c_arretStation.STOP_SEQUENCE||':'||vStopName||'('||c_arretStation.ARRIVAL_TIME||'-'||c_arretStation.DEPARTURE_TIME||')');
				end case;
				compteur := compteur +1;
			end loop;
		end loop;
	end affichageTronLigne;
	
	function tronconsPrivee
		return table_type pipelined as
			cursor trons is
				select t.trip_id as id,c.service_id from calendar c,trips t
					where sysdate() between c.start_date and c.end_date
						and t.service_id=c.service_id ;
		v row_type ;
	begin
		for myrow in trons loop		
			v := row_type(myrow.id);
			pipe row (v);
		end loop;	
		return;
	end tronconsPrivee;
	
	procedure affichageHoraire is
	cursor trons is
		select * from table(tronconsPrivee());
	begin	
		for c_trons in trons loop
				affichageTronLigne(c_trons.tripsid);
		end	loop;
	end affichageHoraire;
	
	function calculeDuTemps (tripid trips.trip_id%type,arrive stops.stop_id%type,depart stops.stop_id%type)
	return number is		
		vDepart stop_times.departure_time%type;
		vArri	stop_times.arrival_time%type;
		i number;
	begin
		select ceil((to_date(vArri,'HH24-MI-SS')-to_date(vDepart,'HH24-MI-SS'))* 24 * 60 * 60) into i from (
			select ARRIVAL_TIME as vArri from stop_times
			where STOP_ID=arrive and TRIP_ID=tripid
			) ,
			(
			select DEPARTURE_TIME as vDepart from stop_times
			where STOP_ID=depart and TRIP_ID=tripid	
			);
		return i;
	end calculeDuTemps;
	
	procedure partirArret(arrive stops.stop_id%type) is
		cursor arrets(parentid stops.parent_station%type) is
			select stop_id,stop_code,stop_name,parent_station
				from stops where parent_station=parentid;
		vParentID stops.parent_station%type;
	begin
		select parent_station into vParentID from stops
			where stop_id=arrive;	
		for c_arrets in arrets(vParentID) loop
			DBMS_OUTPUT.PUT_LINE('stop_id:'||c_arrets.stop_id||' stop_code:'||c_arrets.stop_code||' stop_name:'||c_arrets.stop_name||' parent_station:'||c_arrets.parent_station);
		end loop;
	end partirArret;
end TravailFaire;
/

----TEST (I)----------
--trip_id:4503603927916040
execute TravailFaire.affichageTronLigne(4503603927916040);
	show errors;
l;
------TEST (ii)
declare
	cursor trons is
		select * from table(TravailFaire.tronconsPrivee());
begin
	for c_trons in trons loop
		DBMS_OUTPUT.PUT_LINE(c_trons.tripsid);
	end	loop;
end;
/
	show errors;
l;
-------TEST (III)-----------
execute TravailFaire.affichageHoraire();
	show errors;
l;
--------------TEST (iv)----------------------
--trip_id:4503603927916039
--arrive:3377699720882984
--depart:3377699720883015
declare
	i number;
begin
	i := TravailFaire.calculeDuTemps(4503603927916039,3377699720882984,3377699720883015);
	DBMS_OUTPUT.PUT_LINE(i||' secondes');
end;
/
-----------------TEST (v)-----------------------
--ParentID:1970324837185362
--arriveID:3377699720882984
execute TravailFaire.partirArret(3377699720882984);

-------------------------------------------------------
--*********************Q3****************************--
-------------------------------------------------------
-----chercher les plus haute nieaux
create or replace procedure partirArretHierarchique(arrive stops.stop_id%type) is
	cursor arrets(parentid stops.parent_station%type) is
		select stop_id,stop_code,stop_name,parent_station from stops 
			connect by stop_id= prior PARENT_STATION
			start with stop_id=parentid;
	vParentID stops.parent_station%type;
begin
	select parent_station into vParentID from stops
		where stop_id=arrive;	
	for c_arrets in arrets(vParentID) loop
		DBMS_OUTPUT.PUT_LINE('stop_id:'||c_arrets.stop_id||' stop_code:'||c_arrets.stop_code||' stop_name:'||c_arrets.stop_name||' parent_station:'||c_arrets.parent_station);
	end loop;
end;
/
-----chercher les plus base nieaux
create or replace procedure partirArretHierarchique(arrive stops.stop_id%type) is
	cursor arrets(parentid stops.parent_station%type) is
		select stop_id,stop_code,stop_name,parent_station from stops 
			connect by prior stop_id=  PARENT_STATION
			start with stop_id=parentid;
	vParentID stops.parent_station%type;
begin
	select parent_station into vParentID from stops
		where stop_id=arrive;	
	for c_arrets in arrets(vParentID) loop
		DBMS_OUTPUT.PUT_LINE('stop_id:'||c_arrets.stop_id||' stop_code:'||c_arrets.stop_code||' stop_name:'||c_arrets.stop_name||' parent_station:'||c_arrets.parent_station);
	end loop;
end;
/
--ParentID:1970324837185362
--arriveID:3377699720882984
execute partirArretHierarchique(3377699720882984);
-------------------------------------------------------
--*********************Q4****************************--
-------------------------------------------------------
Mascard:3377699720883026 3377699720883027
Perisse:3377699720883077 3377699720883078

------------cette function pour retourner le nom de station
create or replace function chercherStation(vStop_id STOPS.STOP_ID%type)
return varchar2 is
	vStop_name varchar2(50);
begin
	select stop_name into vStop_name
		from stops
		where stop_id=vStop_id;
	return vStop_name;
end;
/
----------Afficher les information de la route
create or replace procedure chercherRoutes(vTrip_id Trips.trip_id%type) is
	vroute_short_name routes.route_short_name%type;
	vroute_long_name routes.route_long_name%type;
	vroute_type routes.route_type%type;
	vroute_id routes.route_id%type;
	routeType varchar2(50);
begin
	select route_id into vroute_id from trips
		where trip_id=vTrip_id;
	select route_short_name,route_long_name,route_type 
		into vroute_short_name,vroute_long_name,vroute_type
		from Routes
		where route_id=vroute_id;
	case
		when vroute_type=0 then routeType:='Tram';
		when vroute_type=1 then routeType:='Metro';
		when vroute_type=3 then routeType:='Bus';
	end case;
	DBMS_OUTPUT.PUT_LINE('NO.'||vroute_short_name||' Name:'||vroute_long_name||' TYPE:'||routeType);
end;
/
show errors;
l;
---------Afficher les information de troncon en croissant stop_sequence
create or replace procedure lesTrajets (tripid trips.trip_id%type,arrive stop_times.stop_id%type,depart stop_times.stop_id%type) is		
	cursor c1 is
		select * from stop_times
			where trip_id=tripid
				and STOP_SEQUENCE between 
					(select STOP_SEQUENCE from stop_times
						where trip_id=tripid
							and stop_id=depart) 
					and 
					(select STOP_SEQUENCE from stop_times
						where trip_id=tripid
							and stop_id=arrive)
			order by STOP_SEQUENCE;
	vDepart stop_times.departure_time%type;
	vArri	stop_times.arrival_time%type;
	Flag number;
begin
	Flag :=1;
	for c_ligne in c1 loop
		if(Flag=1) then 
			chercherRoutes(c_ligne.trip_id);
			DBMS_OUTPUT.PUT_LINE('STOP_ID:'||chercherStation(c_ligne.stop_id)||' STOP_SEQUENCE:'||c_ligne.stop_sequence ||' ARRIVAL_TIME:'||c_ligne.arrival_time||' DEPARTURE_TIME:'||c_ligne.departure_time);
		else
			DBMS_OUTPUT.PUT_LINE('STOP_ID:'||chercherStation(c_ligne.stop_id)||' STOP_SEQUENCE:'||c_ligne.stop_sequence ||' ARRIVAL_TIME:'||c_ligne.arrival_time||' DEPARTURE_TIME:'||c_ligne.departure_time);
		end if;
		Flag := Flag+1;
	end loop;
end;
/
	show errors;
l;
create or replace procedure Gestion_Trajet(idDepar stops.stop_id%type,idArrive stops.stop_id%type) is		
	vTRIP_ID_Depart stop_times.TRIP_ID%type;
	vStop_id_Depart stop_times.stop_id%type;
	vINTERSECTION_ID_Depart stop_times.stop_id%type;	
	vTRIP_ID_Arrive stop_times.TRIP_ID%type;
	vStop_id_Arrive stop_times.stop_id%type;
	vINTERSECTION_ID_Arrive stop_times.stop_id%type;
begin
	select st1.trip_id,st1.stop_id,st2.stop_id into
			vTRIP_ID_Depart,vStop_id_Depart,vStop_id_Arrive
		from stop_times st1,stop_times st2
			where st1.stop_id=idDepar
			and st2.stop_id=idArrive
			and st1.trip_id=st2.trip_id
			and to_date(st2.ARRIVAL_TIME,'HH24-MI-SS')>=to_date(st1.DEPARTURE_TIME,'HH24-MI-SS')
			and rownum=1;
		lesTrajets(vTRIP_ID_Depart,vStop_id_Arrive,vStop_id_Depart);
EXCEPTION
	WHEN NO_DATA_FOUND THEN
		select a.trip_id,a.depart,s1.stop_id,b.trip_id,b.arrive,s2.stop_id into
			vTRIP_ID_Depart,vStop_id_Depart,vINTERSECTION_ID_Depart,
			vTRIP_ID_Arrive,vStop_id_Arrive,vINTERSECTION_ID_Arrive
			from
			(
				select a.*,b.stop_id as depart
				 from stop_times a,stop_times b
				where b.stop_id=idDepar
				and a.TRIP_ID=b.TRIP_ID			
				and to_date(b.DEPARTURE_TIME,'HH24-MI-SS')<=to_date(a.ARRIVAL_TIME,'HH24-MI-SS')
			) a,
			(
				select a.*,b.stop_id as arrive
				 from stop_times a,stop_times b
				where b.stop_id=idArrive
				and a.TRIP_ID=b.TRIP_ID
				and to_date(b.ARRIVAL_TIME,'HH24-MI-SS')>=to_date(a.DEPARTURE_TIME,'HH24-MI-SS')
			) b,stops s1,stops s2
		where a.STOP_ID=s1.stop_id
		and b.STOP_ID=s2.stop_id
		and s1.stop_name=s2.stop_name
		and to_date(a.ARRIVAL_TIME,'HH24-MI-SS')<=to_date(b.ARRIVAL_TIME,'HH24-MI-SS')
		and rownum=1;	
		lesTrajets(vTRIP_ID_Depart,vINTERSECTION_ID_Depart,vStop_id_Depart);
		DBMS_OUTPUT.PUT_LINE('-----------------------INTERSECTION-----------------------------');
		lesTrajets(vTRIP_ID_Arrive,vStop_id_Arrive,vINTERSECTION_ID_Arrive);
end;
/
	show errors;
l;

----------test---intersection
execute Gestion_Trajet(3377699720883026,3377699720883077);
	show errors;
l;
--------test-----meme ligne
execute Gestion_Trajet(3377699720881222,3377699720880735);


-------------------------------------------------------
--*********************BONUS****************************--
-------------------------------------------------------
create or replace procedure Gestion_Trajet_BONUS(idDepar stops.stop_id%type,idArrive stops.stop_id%type,HDep stop_times.ARRIVAL_TIME%type) is		
	vTRIP_ID_Depart stop_times.TRIP_ID%type;
	vStop_id_Depart stop_times.stop_id%type;
	vINTERSECTION_ID_Depart stop_times.stop_id%type;	
	vTRIP_ID_Arrive stop_times.TRIP_ID%type;
	vStop_id_Arrive stop_times.stop_id%type;
	vINTERSECTION_ID_Arrive stop_times.stop_id%type;
begin
	select tripid,stop_id_depart,stop_id_arrive into
			vTRIP_ID_Depart,vStop_id_Depart,vStop_id_Arrive
		from (
			select st1.trip_id as tripid,st1.stop_id as stop_id_depart,st2.stop_id as stop_id_arrive
			from stop_times st1,stop_times st2
				where st1.stop_id=idDepar
				and st2.stop_id=idArrive
				and st1.trip_id=st2.trip_id
				and to_date(st2.ARRIVAL_TIME,'HH24-MI-SS')>=to_date(st1.DEPARTURE_TIME,'HH24-MI-SS')
				and TO_DATE(HDep,'HH24-MI-SS') <=TO_DATE(st1.ARRIVAL_TIME,'HH24-MI-SS')
				order by TO_DATE(st1.ARRIVAL_TIME,'HH24-MI-SS')
			)
		where rownum=1;
		lesTrajets(vTRIP_ID_Depart,vStop_id_Arrive,vStop_id_Depart);
EXCEPTION
	WHEN NO_DATA_FOUND THEN
		select a.trip_id,a.depart,s1.stop_id,b.trip_id,b.arrive,s2.stop_id into
			vTRIP_ID_Depart,vStop_id_Depart,vINTERSECTION_ID_Depart,
			vTRIP_ID_Arrive,vStop_id_Arrive,vINTERSECTION_ID_Arrive
			from
			(
				select a.*,b.stop_id as depart
				 from stop_times a,stop_times b
				where b.stop_id=idDepar
				and a.TRIP_ID=b.TRIP_ID			
				and TO_DATE(HDep,'HH24-MI-SS') <=TO_DATE(b.ARRIVAL_TIME,'HH24-MI-SS')
				and to_date(b.DEPARTURE_TIME,'HH24-MI-SS')<=to_date(a.ARRIVAL_TIME,'HH24-MI-SS')
				order by TO_DATE(b.ARRIVAL_TIME,'HH24-MI-SS')
			) a,
			(
				select a.*,b.stop_id as arrive
				 from stop_times a,stop_times b
				where b.stop_id=idArrive
				and a.TRIP_ID=b.TRIP_ID
				and to_date(b.ARRIVAL_TIME,'HH24-MI-SS')>=to_date(a.DEPARTURE_TIME,'HH24-MI-SS')
			) b,stops s1,stops s2
		where a.STOP_ID=s1.stop_id
		and b.STOP_ID=s2.stop_id
		and s1.stop_name=s2.stop_name
		and to_date(a.ARRIVAL_TIME,'HH24-MI-SS')<=to_date(b.ARRIVAL_TIME,'HH24-MI-SS')
		and rownum=1;	
		lesTrajets(vTRIP_ID_Depart,vINTERSECTION_ID_Depart,vStop_id_Depart);
		DBMS_OUTPUT.PUT_LINE('-----------------------INTERSECTION-----------------------------');
		lesTrajets(vTRIP_ID_Arrive,vStop_id_Arrive,vINTERSECTION_ID_Arrive);
end;
/
	show errors;
l;	
--------test-----intersection
execute Gestion_Trajet_BONUS(3377699720883026,3377699720883077,'05:42:00');	
execute Gestion_Trajet_BONUS(3377699720883078,3377699720883027,'05:42:00');

--------test-----meme ligne
execute Gestion_Trajet_BONUS(3377699720881222,3377699720880735,'05:42:00');	