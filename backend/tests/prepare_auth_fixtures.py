"""Prepare ignored fictional Auth fixtures for the dedicated development project.

Apply the generated create SQL through an authorized server-side connection.
Always apply cleanup SQL afterward, including if an API/browser test fails.
This deliberately bypasses email delivery; it does not verify email callbacks.
"""
import json
from pathlib import Path
import secrets
import uuid

root = Path(__file__).resolve().parents[2]
config = json.loads((root / 'config/supabase.local.json').read_text())
if config['SUPABASE_URL'] != 'https://hgsivbqmbcliqbstrkdz.supabase.co':
    raise SystemExit('Fixtures are restricted to the dedicated development project.')
accounts_path = root / 'config/auth-test.local.json'
sql_path = root / 'config/auth-fixtures.local.json'
if accounts_path.exists() or sql_path.exists():
    raise SystemExit('Existing fixtures must be cleaned up before preparing new ones.')
accounts = [dict(id=str(uuid.uuid4()), email=f'adult-{uuid.uuid4().hex}@example.invalid',
                 password=secrets.token_hex(18)) for _ in range(2)]
queries = ['begin;']
for account in accounts:
    # All interpolated values are locally generated UUIDs/hex, never user input.
    uid, email, password = account['id'], account['email'], account['password']
    queries.append(f"""insert into auth.users
      (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
       confirmation_token,recovery_token,email_change_token_new,email_change,
       raw_app_meta_data,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values ('00000000-0000-0000-0000-000000000000','{uid}',
       'authenticated','authenticated','{email}',
       extensions.crypt('{password}',extensions.gen_salt('bf')),now(),'','','','',
       '{{"provider":"email","providers":["email"]}}','{{}}',false,now(),now());""")
    queries.append(f"""insert into auth.identities
      (id,user_id,provider_id,identity_data,provider,created_at,updated_at)
      values (gen_random_uuid(),'{uid}','{uid}',
       '{{"sub":"{uid}","email":"{email}"}}','email',now(),now());""")
queries.append('commit;')
ids = ','.join(f"'{account['id']}'" for account in accounts)
cleanup = f"delete from auth.users where id in ({ids}); select count(*) as remaining_test_accounts from auth.users where id in ({ids});"
accounts_path.write_text(json.dumps(accounts), encoding='utf-8')
reset_originals = f"update public.original_assets a set state='pending' from public.families f where f.id=a.family_id and f.parent_user_id in ({ids});"
sql_path.write_text(json.dumps(dict(create='\n'.join(queries), cleanup=cleanup, reset_originals=reset_originals)), encoding='utf-8')
print('Prepared ignored fictional account/SQL files. Credentials omitted.')
