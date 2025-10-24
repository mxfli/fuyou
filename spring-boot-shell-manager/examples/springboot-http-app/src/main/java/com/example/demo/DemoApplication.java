package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

/**
 * Spring Boot 测试应用
 * 用于测试 startup.sh 脚本的各项功能
 */
@SpringBootApplication
@RestController
public class DemoApplication {

    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private LocalDateTime startTime;

    public static void main(String[] args) {
        System.out.println("=== Spring Boot Test Application Starting ===");
        System.out.println("启动时间: " + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        System.out.println("监听端口: 8801");
        System.out.println("Actuator端点: http://localhost:8801/actuator");
        System.out.println("健康检查: http://localhost:8801/actuator/health");
        System.out.println("应用信息: http://localhost:8801/actuator/info");
        System.out.println("优雅停止: POST http://localhost:8801/actuator/shutdown");
        System.out.println("===============================================");
        
        SpringApplication.run(DemoApplication.class, args);
    }

    @PostConstruct
    public void init() {
        startTime = LocalDateTime.now();
        System.out.println("应用初始化完成: " + startTime.format(FORMATTER));
    }

    @PreDestroy
    public void destroy() {
        System.out.println("应用正在关闭: " + LocalDateTime.now().format(FORMATTER));
        System.out.println("运行时长: " + java.time.Duration.between(startTime, LocalDateTime.now()).getSeconds() + " 秒");
    }

    /**
     * 根路径 - 应用信息
     */
    @GetMapping("/")
    public Map<String, Object> home() {
        Map<String, Object> info = new HashMap<>();
        info.put("application", "Spring Boot Test App");
        info.put("version", "1.0.0");
        info.put("port", 8801);
        info.put("startTime", startTime.format(FORMATTER));
        info.put("currentTime", LocalDateTime.now().format(FORMATTER));
        info.put("uptime", java.time.Duration.between(startTime, LocalDateTime.now()).getSeconds() + " seconds");
        info.put("status", "running");
        info.put("message", "应用运行正常，可用于测试 startup.sh 脚本功能");
        return info;
    }

    /**
     * 健康检查端点
     */
    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("timestamp", LocalDateTime.now().format(FORMATTER));
        Map<String, String> checks = new HashMap<>();
        checks.put("application", "UP");
        checks.put("database", "UP");
        checks.put("diskSpace", "UP");
        health.put("checks", checks);
        return health;
    }

    /**
     * 测试端点 - 模拟业务功能
     */
    @GetMapping("/api/test")
    public Map<String, Object> test() {
        Map<String, Object> result = new HashMap<>();
        result.put("message", "测试接口调用成功");
        result.put("timestamp", LocalDateTime.now().format(FORMATTER));
        Map<String, Object> data = new HashMap<>();
        data.put("userId", 12345);
        data.put("userName", "testUser");
        data.put("operation", "startup.sh script test");
        result.put("data", data);
        return result;
    }

    /**
     * 系统信息端点
     */
    @GetMapping("/api/system")
    public Map<String, Object> system() {
        Runtime runtime = Runtime.getRuntime();
        Map<String, Object> system = new HashMap<>();
        system.put("javaVersion", System.getProperty("java.version"));
        system.put("javaVendor", System.getProperty("java.vendor"));
        system.put("osName", System.getProperty("os.name"));
        system.put("osVersion", System.getProperty("os.version"));
        system.put("totalMemory", runtime.totalMemory() / 1024 / 1024 + " MB");
        system.put("freeMemory", runtime.freeMemory() / 1024 / 1024 + " MB");
        system.put("maxMemory", runtime.maxMemory() / 1024 / 1024 + " MB");
        system.put("processors", runtime.availableProcessors());
        return system;
    }

    /**
     * 模拟长时间运行的任务 - 用于测试优雅停止
     */
    @GetMapping("/api/long-task")
    public Map<String, Object> longTask() throws InterruptedException {
        System.out.println("开始执行长时间任务: " + LocalDateTime.now().format(FORMATTER));
        
        // 模拟10秒的长时间任务
        for (int i = 1; i <= 10; i++) {
            Thread.sleep(1000);
            System.out.println("长时间任务进度: " + i + "/10");
        }
        
        Map<String, Object> result = new HashMap<>();
        result.put("message", "长时间任务执行完成");
        result.put("duration", "10 seconds");
        result.put("completedAt", LocalDateTime.now().format(FORMATTER));
        
        System.out.println("长时间任务完成: " + LocalDateTime.now().format(FORMATTER));
        return result;
    }
}