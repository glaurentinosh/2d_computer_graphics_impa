# 2d_computer_graphics_impa
This is the project developed during a summer course on 2D Computer Graphics at IMPA, Brazil.

This is a driver that renders .rvg files (vector graphics) into .png files.


1. Install WSL 2 and Docker
2. Extract zip files from src.zip
3. Run:

```bash
docker run -it --rm \
           -e USER=$$\(id -u -n\) \
           -e GROUP=$$\(id -g -n\) \
           -e UID=$$\(id -u\) \
           -e GID=$$\(id -g\) \
           -w /home/$$\(id -u -n\) \
           -v `pwd`:/home/$$\(id -u -n\)/host \
           diegonehab/vg
```


4. Inside src-1.0.1, run 

```bash
make
```

5. To use my driver, run 

```bash
luapp proccess.lua gabriel-laurentino file.rvg file.png
```

More info available in: http://w3.impa.br/~diego/teaching/vg/
