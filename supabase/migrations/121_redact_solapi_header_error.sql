-- SOLAPI 인증 헤더에 포함된 API Key가 과거 오류 메시지에 남지 않도록 정리한다.
update public.message_logs
set error_message = '솔라피 API Key 형식 오류를 수정했습니다. 다시 시도해 주세요.'
where status = 'failed'
  and error_message ilike 'Invalid header value:%';
