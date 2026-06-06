## Now apply template to container

```sh
bastille create lnms 14.1-RELEASE YourIP-Bastille
bastille bootstrap https://github.com/bastille-templates/librenms
bastille template lnms bastille-templates/librenms \
  --arg MY_VERSION=80 \
  --arg MY_PORT=3306 \
  --arg CPULIMIT=0,1 \
  --arg MEMLIMIT=4096M \
  --arg DISKLIMIT=32G
```

## License

This project is licensed under the BSD-3-Clause license.
