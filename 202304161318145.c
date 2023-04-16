#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/in.h>
#include <net/sock.h>
#include <linux/inet.h>
#include <linux/fdtable.h>
#include <net/inet_sock.h>
MODULE_LICENSE("GPL");

static int pid = -1; // 默认的PID为-1，表示未指定

module_param(pid, int, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP); // 可通过模块参数指定PID

static int __init my_init(void)
{
    struct sock *sk; // 定义套接字
    struct inet_sock *inet; // 定义INET套接字
    struct task_struct *task; // 定义进程任务结构体

    printk(KERN_INFO "Module loaded\n");

    if (pid < 0) {
        printk(KERN_INFO "PID not specified. Exiting.\n");
        return -1;
    }

    rcu_read_lock(); // 读取进程列表时加锁

    task = pid_task(find_vpid(pid), PIDTYPE_PID); // 根据PID获取进程任务结构体

    if (!task) {
        printk(KERN_INFO "Invalid PID. Exiting.\n");
        rcu_read_unlock();
        return -1;
    }

    sk = task->files->fdt->fd[task->files->fdt->max_fds-1]->private_data;// 获取进程文件描述符的套接字
    inet = inet_sk(sk); // 转换为INET套接字

    printk(KERN_INFO "Process %d is accessing IP %pI4:%d\n", pid, &inet->inet_saddr, ntohs(inet->inet_sport)); // 输出IP地址和端口号

    rcu_read_unlock(); // 释放锁

    return 0;
}

static void __exit my_exit(void)
{
    printk(KERN_INFO "Module unloaded\n");
}

module_init(my_init);
module_exit(my_exit);

