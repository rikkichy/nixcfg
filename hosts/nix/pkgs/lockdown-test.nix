{ runCommand, python3, openssl, kmod, cpio, gzip, qemu, pkgsStatic, kernel }:

runCommand "lockdown-kernel-smoke" {
  nativeBuildInputs = [ python3 openssl kmod cpio gzip qemu ];
} ''
  python3 ${./verify-lockdown-modules.py} ${kernel} ${kernel.modDirVersion}
  mkdir -p root/bin root/proc root/sys root/dev root/tmp
  cp ${pkgsStatic.busybox}/bin/busybox root/bin/busybox
  ln -s busybox root/bin/sh
  cat > root/init <<'EOF'
  #!/bin/sh
  export PATH=/bin
  /bin/busybox --install -s /bin
  mount -t proc proc /proc
  mount -t sysfs sysfs /sys
  mount -t devtmpfs devtmpfs /dev
  mount -t securityfs securityfs /sys/kernel/security
  fail() {
    echo "LOCKDOWN_SMOKE_FAILED: $*"
    poweroff -f
    exit 1
  }
  case "$(cat /sys/kernel/security/lockdown)" in
    *'[integrity]'*) ;;
    *) fail 'integrity lockdown is inactive' ;;
  esac
  case ",$(cat /sys/kernel/security/lsm)," in
    *,bpf,*) ;;
    *) fail 'BPF LSM is inactive' ;;
  esac
  sh /load-dummy.sh || fail 'signed module rejected'
  rmmod dummy || fail 'cannot unload test module'
  if insmod /unsigned-dummy.ko; then
    fail 'unsigned module accepted'
  fi
  if insmod /tampered-dummy.ko; then
    fail 'tampered signature accepted'
  fi
  sh /load-v4l2loopback.sh || fail 'signed camera modules rejected'
  test -d /sys/module/v4l2loopback || fail 'camera module is absent'
  test -e /sys/class/video4linux/video0 || fail 'camera device is absent'
  echo LOCKDOWN_SMOKE_OK
  poweroff -f
  EOF
  chmod +x root/init
  (cd root && find . -print0 | cpio --null -o -H newc) | gzip -n > initrd.gz

  timeout 180 qemu-system-x86_64 \
    -machine accel=kvm:tcg -cpu max -smp 2 -m 1024 \
    -display none -serial stdio -monitor none -no-reboot -nic none \
    -kernel ${kernel}/bzImage -initrd initrd.gz \
    -append 'console=ttyS0 panic=-1 lockdown=integrity lsm=landlock,yama,bpf' \
    > boot.log 2>&1 || { cat boot.log; exit 1; }
  cat boot.log
  grep -q '^LOCKDOWN_SMOKE_OK' boot.log
  if grep -q 'LOCKDOWN_SMOKE_FAILED' boot.log; then exit 1; fi
  mkdir "$out"
  cp boot.log "$out/"
''
