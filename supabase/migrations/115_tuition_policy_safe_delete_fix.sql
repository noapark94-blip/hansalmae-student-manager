-- 운영 DB의 safe-update 정책에 맞게 결합 할인 초기화를 명시적 조건 삭제로 변경합니다.

create or replace function public.staff_save_tuition_fee_policy(
  p_groups jsonb,
  p_mappings jsonb,
  p_discounts jsonb,
  p_month date,
  p_apply_current boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  calculated jsonb;
  charge_row record;
  updated_count integer := 0;
  skipped_paid_count integer := 0;
begin
  if not public.is_staff() then raise exception '교직원만 원비 정책을 저장할 수 있습니다.'; end if;
  if jsonb_typeof(p_groups)<>'array' or jsonb_typeof(p_mappings)<>'array' or jsonb_typeof(p_discounts)<>'array' then
    raise exception '원비 정책 형식을 확인해 주세요.';
  end if;

  for item in select value from jsonb_array_elements(p_groups) loop
    if (item->>'amount') is not null and ((item->>'amount')::numeric<0 or (item->>'amount')::numeric<>trunc((item->>'amount')::numeric)) then
      raise exception '기본 원비를 확인해 주세요.';
    end if;
    update public.tuition_fee_groups
    set amount=case when (item->>'amount') is null then null else (item->>'amount')::integer end,
        active=coalesce((item->>'active')::boolean,true),updated_at=now()
    where id=(item->>'id')::uuid;
    if not found then raise exception '원비 그룹을 찾을 수 없습니다.'; end if;
  end loop;

  for item in select value from jsonb_array_elements(p_mappings) loop
    if coalesce(item->>'groupId','')='' then
      delete from public.tuition_subject_group_mappings
      where subject_id=(item->>'subjectId')::uuid and school_level=item->>'schoolLevel';
    else
      insert into public.tuition_subject_group_mappings(subject_id,school_level,fee_group_id)
      values((item->>'subjectId')::uuid,item->>'schoolLevel',(item->>'groupId')::uuid)
      on conflict(subject_id,school_level) do update set fee_group_id=excluded.fee_group_id;
    end if;
  end loop;

  delete from public.tuition_combination_discounts where id is not null;
  for item in select value from jsonb_array_elements(p_discounts) loop
    if (item->>'amount')::numeric<0 or jsonb_array_length(item->'groupIds')<2 then
      raise exception '결합 할인 조건을 확인해 주세요.';
    end if;
    insert into public.tuition_combination_discounts(
      id,school_level,name,amount,required_group_ids,active
    ) values(
      coalesce((item->>'id')::uuid,gen_random_uuid()),item->>'schoolLevel',
      trim(item->>'name'),(item->>'amount')::integer,
      array(select jsonb_array_elements_text(item->'groupIds')::uuid),
      coalesce((item->>'active')::boolean,true)
    );
  end loop;

  if p_apply_current then
    for charge_row in
      select tc.*,
        exists(select 1 from public.tuition_payments tp where tp.charge_id=tc.id) has_payment
      from public.tuition_charges tc
      where tc.billing_month=date_trunc('month',p_month)::date
      for update
    loop
      if charge_row.has_payment then skipped_paid_count:=skipped_paid_count+1; continue; end if;
      calculated:=public.calculate_student_tuition_policy(charge_row.student_id,p_month);
      if jsonb_array_length(calculated->'missingGroups')>0 then continue; end if;
      update public.tuition_charges set
        line_items=calculated->'lineItems',
        base_amount=(calculated->>'baseAmount')::integer,
        discount_amount=(calculated->>'discountAmount')::integer,
        additional_amount=(calculated->>'additionalAmount')::integer,
        memo=calculated->>'memo',
        updated_at=now()
      where id=charge_row.id;
      perform public.refresh_tuition_charge_status(charge_row.id);
      updated_count:=updated_count+1;
    end loop;
  end if;

  return jsonb_build_object('updated',updated_count,'skippedPaid',skipped_paid_count);
end
$$;
