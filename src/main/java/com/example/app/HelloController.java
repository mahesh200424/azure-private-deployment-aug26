package com.example.app;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class HelloController {

    @GetMapping("/")
    public Map<String, String> hello() {
        return Map.of(
            "message", "SpendGenie Azure Private Deployment",
            "status",  "running",
            "version", "1.0.0"
        );
    }

    @GetMapping("/healthz/live")
    public Map<String, String> liveness() {
        return Map.of("status", "UP");
    }

    @GetMapping("/healthz/ready")
    public Map<String, String> readiness() {
        return Map.of("status", "UP");
    }
}
