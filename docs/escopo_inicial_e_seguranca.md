# Escopo inicial e segurança

## Escopo liberado nesta fase

O menu principal expõe somente:

- Página inicial;
- Estoque;
- Cadastro em massa;
- Configurações.

Os módulos de mapa, SMS, logs e demais áreas continuam no código para
compatibilidade e evolução, mas não são caminhos de navegação desta fase.

## Banco local SQL e credenciais das integrações

O login operacional usa `accounts:signInWithPassword` do BancoLocalSQL Auth. O
BancoLocalSQL Auth não devolve nem armazena a senha em texto; a senha fica sob o
controle do provedor de autenticação. O token de sessão é mantido em memória e
o refresh token legado é protegido pelo cofre local apenas para compatibilidade
com instalações já configuradas.

As credenciais das integrações são sincronizadas em
`credentials/{branch_id}`. O aplicativo só lê e grava o conjunto da filial
autenticada. A autorização publicada usa o cadastro do próprio BancoLocalSQL em
`access/users/{uid}`:

- `branches/{branch_id} = true`: filial autorizada;
- `can_write = true`: permite alterações no estoque e nas credenciais;
- o UID administrador pode gerenciar usuários, filiais e o estado global.

Não trate a Web API Key do BancoLocalSQL como senha: ela identifica o projeto, mas
não deve conceder acesso sozinha. O controle real é feito pelo BancoLocalSQL Auth,
pelas regras do banco SQLite local e pelo cadastro autorizado em
`access/users/{uid}`.

## Backup local diário

Após cada snapshot confirmado do BancoLocalSQL, o sistema grava no máximo um backup
por dia para a filial aberta em:

```text
<diretorio do projeto>/backups/backups_<filial>/inventory_auto_AAAA-MM-DD.json
```

Em uma versão exportada, o diretório-base passa a ser o diretório do
executável. São mantidos os últimos 14 dias por filial. O backup contém um
envelope com data, filial lógica, origem BancoLocalSQL e snapshot do estoque.

## Limite importante

Guardar credenciais de terceiros no banco SQLite local permite que qualquer
cliente com claims `credentials_read` as receba em memória, pois ele precisa
usá-las para chamar as APIs externas. Para produção, o desenho mais forte é um
backend/Cloud Function que mantém essas credenciais e entrega apenas leases
temporárias ao aplicativo. O broker remoto já existente no projeto pode ser
usado nessa próxima etapa.
