-- Migration: 20261030151000_seed_phone_numbers.sql
-- Assign contact phone numbers for the primary Ciro High School accounts so users can log in via phone number.

update public.users
set phone_number = '+251911000001'
where id = 'bf883616-97a1-4797-8455-1d8df34917fa' and (phone_number is null or phone_number = '');

update public.users
set phone_number = '+251911000002'
where id = 'd557428f-aaf7-420f-a170-f6a081586b6f' and (phone_number is null or phone_number = '');

update public.users
set phone_number = '+251911000003'
where id = 'e587ca15-302a-403c-aec3-e2e64f325f3c' and (phone_number is null or phone_number = '');

update public.users
set phone_number = '+251911000004'
where id = 'c201a569-dfdc-4494-bf8a-3b0d20f88c2c' and (phone_number is null or phone_number = '');
