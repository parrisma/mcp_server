## Keycloak

### hosts
Add this to both WSL and Windows hosts
```
sudo vi /etc/hosts
(admin shell) notepad "$env:SystemRoot\System32\drivers\etc\hosts"
192.168.0.54   keycloak.parris3142.com
```
where 192.68.0.54 is docker internal host

```
ipconfig /flushdns
```

check on windows with

```
curl.exe -vk https://keycloak.parris3142.com
```

portainer: admin : passwordpassword :https://portainer.test/
openwebui : admin@admin.com : password : https://openwebui.test/
openwebui : (via key cloak) : test : password : https://openwebui.test/
traefik: - : - : http://traefik.test/
keycloak: admin : password : https://keycloak.test/