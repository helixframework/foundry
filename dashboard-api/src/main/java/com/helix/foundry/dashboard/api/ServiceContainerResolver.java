package com.helix.foundry.dashboard.api;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class ServiceContainerResolver {
  @Value("${GITEA_CONTAINER_NAME:gitea}")
  private String giteaContainerName;

  @Value("${TEAMCITY_SERVER_CONTAINER_NAME:teamcity-server}")
  private String teamcityContainerName;

  @Value("${NEXUS_CONTAINER_NAME:nexus}")
  private String nexusContainerName;

  @Value("${BUILD_CACHE_CONTAINER_NAME:build-cache}")
  private String buildCacheContainerName;

  public String resolveContainerName(String serviceId) {
    return switch (serviceId) {
      case "gitea" -> giteaContainerName;
      case "teamcity" -> teamcityContainerName;
      case "nexus" -> nexusContainerName;
      case "build-cache" -> buildCacheContainerName;
      default -> null;
    };
  }
}
