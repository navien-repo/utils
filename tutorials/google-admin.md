# HAL · Google Admin

## Rode o script

Clique em **Start**. Depois clique no ícone de terminal ao lado do comando abaixo e aperte **Enter**:

```bash
bash scripts/google-admin-setup.sh
```

O script cria o projeto **HAL-Project** e a conta de serviço **hal-admin-sa**, e baixa o arquivo **hal-google-admin.json**. Se o download não começar, rode:

```bash
cloudshell download hal-google-admin.json
```

## Devolva o arquivo ao HAL

Volte à aba do HAL e use **Subir o arquivo .json**. O HAL mostra o ID do cliente e os escopos para você autorizar no Admin console.
