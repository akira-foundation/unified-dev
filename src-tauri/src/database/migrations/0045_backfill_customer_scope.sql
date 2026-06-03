UPDATE providers SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
UPDATE projects SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
UPDATE tracker_credentials SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
