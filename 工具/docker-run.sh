sudo docker run --rm -it \
-v /home/{user}/zqz/yocto:/home/zqz/yoccto \
-v /tmp/.X11-unix:/tmp/.X11-unix \
--volume="$HOME/.Xauthority:/home/zqz/.Xauthority:rw" \
-e DISPLAY=$DISPLAY \
--net=host \
--cap-add NET_ADMIN \
--device /dev/net/tun \
--device /dev/kvm \
--name zqz-jenkins-test jenkins-debian /bin/bash
