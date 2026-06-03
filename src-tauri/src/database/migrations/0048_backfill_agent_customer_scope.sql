UPDATE local_repositories SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
UPDATE skills SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
UPDATE mcp_servers SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
