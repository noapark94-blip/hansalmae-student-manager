ALTER TABLE public.tuition_payments DROP CONSTRAINT tuition_payments_payment_method_check;
ALTER TABLE public.tuition_payments ADD CONSTRAINT tuition_payments_payment_method_check CHECK (payment_method IN ('cash','transfer','card','siru','other'));
