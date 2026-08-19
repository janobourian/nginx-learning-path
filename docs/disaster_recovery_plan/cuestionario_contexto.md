# Cuestionario de Contexto: Plan de Recuperación ante Desastres (DRP)

Este documento contiene las preguntas que cada equipo debe responder antes de diseñar e implementar el Plan de Recuperación ante Desastres (DRP) multi-región en AWS (us-east-1 ↔ us-west-2). Las respuestas proporcionarán el contexto necesario para definir la estrategia de DR adecuada para cada carga de trabajo.

!!! warning "Importante"
    Todas las preguntas deben ser respondidas **antes** de iniciar el diseño del DRP. Un plan de DR sin contexto completo genera falsa confianza y falla cuando más se necesita.

---

## Equipo de Gestión / Management

### Objetivos de Negocio

- [ ] ¿Cuáles son las aplicaciones y servicios más críticos para el negocio? Ordenar por prioridad.
- [ ] Para cada aplicación/servicio crítico:

| Aplicación/Servicio | Impacto si no está disponible 1 hora | Impacto si no está disponible 4 horas | Impacto si no está disponible 24 horas |
| --------------------- | -------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| | |
| | |
| | |

- [ ] ¿Cuál es el costo estimado por hora de inactividad para cada aplicación crítica?
- [ ] ¿Existen obligaciones contractuales (SLAs) con clientes que definan tiempos de disponibilidad?
- [ ] ¿Cuáles son los SLAs comprometidos? (ej. 99.9%, 99.95%, 99.99%)

### RPO y RTO por Carga de Trabajo

- [ ] Para cada aplicación/servicio, definir:

| Aplicación | RPO (pérdida de datos máxima) | RTO (tiempo de inactividad máximo) | Tier (1=Crítico, 2=Importante, 3=Normal) |
| ------------ | ------------------------------- | ------------------------------------- | ------------------------------------------ |
| | |
| | |
| | |

- [ ] ¿Estos valores de RPO/RTO están aprobados por la dirección?
- [ ] ¿Se ha realizado un análisis de impacto al negocio (BIA) formal?

### Presupuesto y Recursos

- [ ] ¿Cuál es el presupuesto aprobado para la infraestructura de DR?
- [ ] ¿Se entiende que el costo de DR es proporcional a la velocidad de recuperación? (menor RTO = mayor costo)
- [ ] ¿Cuál es el costo mensual actual de la infraestructura en la región primaria?
- [ ] ¿Cuál es el porcentaje adicional aceptable para DR? (típicamente 20-100% del costo primario)
- [ ] ¿Se contratará soporte externo para el diseño o implementación del DRP?
- [ ] ¿Se tiene presupuesto para pruebas de DR regulares (mínimo trimestrales)?

### Gobernanza

- [ ] ¿Quién es el responsable ejecutivo (sponsor) del DRP?
- [ ] ¿Quién tiene la autoridad para declarar un desastre e iniciar el failover?
- [ ] ¿Quién tiene la autoridad para aprobar el failback (regreso a la región primaria)?
- [ ] ¿Existe un comité de crisis o equipo de respuesta a incidentes?
- [ ] ¿Con qué frecuencia se revisará y actualizará el DRP? (mínimo anual recomendado)
- [ ] ¿Existe un proceso de gestión de cambios que aplique al DRP?

### Comunicación

- [ ] ¿Cuál es el plan de comunicación durante un desastre?
- [ ] ¿Quiénes deben ser notificados y en qué orden? (cadena de escalación)
- [ ] ¿Qué canales de comunicación se usarán? (¿Qué pasa si el canal principal también falla?)
- [ ] ¿Se debe notificar a clientes externos? ¿Cómo y en qué plazo?
- [ ] ¿Se debe notificar a reguladores? ¿En qué plazo?
- [ ] ¿Tienen una página de estatus pública? ¿Quién la actualiza?

---

## Equipo de Arquitectura

### Arquitectura Actual

- [ ] ¿Tienen un diagrama de arquitectura actualizado de todos los servicios en producción?
- [ ] ¿Cuáles servicios de AWS se usan actualmente en la región primaria (us-east-1)?

| Categoría | Servicio | ¿Se usa? | Detalles (instancias, configuración) |
| ----------- | ---------- | ---------- | -------------------------------------- |
| Cómputo | EC2 | |
| Cómputo | ECS/Fargate | |
| Cómputo | Lambda | |
| Cómputo | EKS | |
| Base de datos | RDS | Motor, versión, clase de instancia |
| Base de datos | Aurora | Motor, versión, cluster config |
| Base de datos | DynamoDB | Tablas, modo de capacidad |
| Base de datos | ElastiCache | Motor, tipo de nodo |
| Almacenamiento | S3 | Buckets, tamaño total |
| Almacenamiento | EBS | Volúmenes, tipos, tamaños |
| Almacenamiento | EFS | File systems, tamaño |
| Red | VPC | CIDRs, subnets, AZs |
| Red | ALB/NLB | Listeners, target groups |
| Red | CloudFront | Distribuciones |
| Red | Route 53 | Hosted zones, registros |
| Red | API Gateway | APIs, stages |
| Integración | SQS | Colas, tipo (standard/FIFO) |
| Integración | SNS | Topics, suscripciones |
| Integración | EventBridge | Event buses, reglas |
| Seguridad | WAF | Web ACLs, reglas |
| Seguridad | Secrets Manager | Número de secretos |
| Seguridad | KMS | Llaves, tipo |
| Monitoreo | CloudWatch | Dashboards, alarmas |

- [ ] ¿Cuáles servicios son stateful (mantienen estado) y cuáles son stateless?
- [ ] ¿Cuáles servicios son globales (IAM, Route 53, CloudFront) y no necesitan replicación?
- [ ] ¿Existen dependencias entre servicios? Proporcionar diagrama de dependencias.
- [ ] ¿Existen servicios de terceros (SaaS) que también necesiten DR?

### Estrategia de DR por Servicio

- [ ] Para cada servicio, ¿cuál estrategia de DR se recomienda?

| Servicio | Estrategia Recomendada | Justificación |
|----------|------------------------|---------------|
| Backup & Restore / Pilot Light / Warm Standby / Active-Active |
| |

- [ ] ¿Se usará una sola estrategia para todo o diferentes estrategias por tier?
- [ ] ¿Se ha evaluado AWS Elastic Disaster Recovery (DRS) para instancias EC2?
- [ ] ¿Se ha evaluado Aurora Global Database vs RDS Cross-Region Read Replicas?
- [ ] ¿Se usará Route 53 failover, Global Accelerator, o ambos?
- [ ] ¿Se usará Amazon Application Recovery Controller (ARC) para orquestar el failover?

### Infraestructura como Código

- [ ] ¿Toda la infraestructura está definida como código (CloudFormation, CDK, Terraform)?
- [ ] Si no, ¿qué porcentaje está como código y qué se creó manualmente?
- [ ] ¿Se pueden desplegar los templates en la región de DR sin modificaciones?
- [ ] ¿Se usan CloudFormation StackSets para despliegue multi-región?

---

## Equipo de Infraestructura

### Red y Conectividad

- [ ] ¿Cuál es la configuración actual de VPC en us-east-1?

| Atributo | Valor |
| ---------- | ------- |
| VPC CIDR |
| Número de subnets públicas |
| Número de subnets privadas |
| Número de AZs utilizadas |
| ¿Tiene NAT Gateway? |
| ¿Tiene VPN a on-premises? |
| ¿Tiene Direct Connect? |
| ¿Tiene Transit Gateway? |

- [ ] ¿Cuál será el CIDR de la VPC en us-west-2? (debe ser no solapado si se usa peering)
- [ ] ¿Se necesita conectividad entre las dos regiones? ¿Para qué servicios?
- [ ] ¿Se usará VPC Peering o Transit Gateway inter-región?
- [ ] ¿Existe conectividad desde on-premises a ambas regiones?
- [ ] ¿Cuál es el ancho de banda disponible entre regiones?
- [ ] ¿Se necesita que la región de DR tenga acceso a internet (NAT Gateway, IGW)?

### DNS y Tráfico

- [ ] ¿Cuáles dominios y subdominios se usan para las aplicaciones?
- [ ] ¿Los registros DNS están en Route 53 o en otro proveedor?
- [ ] ¿Cuál es el TTL actual de los registros DNS críticos?
- [ ] ¿Se puede reducir el TTL a 60 segundos para los registros de failover?
- [ ] ¿Se usa CloudFront? ¿Con qué orígenes?
- [ ] ¿Se usa Global Accelerator actualmente?

### Cómputo

- [ ] ¿Cuántas instancias EC2 hay en producción? ¿Qué tipos?
- [ ] ¿Se usan Auto Scaling Groups? ¿Con qué configuración (min/max/desired)?
- [ ] ¿Se usan AMIs personalizadas? ¿Con qué frecuencia se actualizan?
- [ ] ¿Se usa Image Builder para crear AMIs?
- [ ] ¿Los contenedores se despliegan en ECS, EKS o ambos?
- [ ] ¿Las imágenes de contenedores están en ECR? ¿Se replica a otra región?
- [ ] ¿Cuántas funciones Lambda hay en producción?
- [ ] ¿Las funciones Lambda se despliegan con IaC?

### Cuotas de Servicio

- [ ] ¿Se han verificado las cuotas de servicio (service quotas) en us-west-2?
- [ ] ¿Las cuotas en us-west-2 son suficientes para soportar la carga de producción completa?
- [ ] ¿Se han solicitado incrementos de cuota en us-west-2? ¿Para qué servicios?

---

## Equipo de Base de Datos (DBA)

### Bases de Datos en Alcance

- [ ] Para cada base de datos en producción:

| Base de Datos | Motor | Versión | Servicio AWS | Tamaño | Clase de Instancia | Multi-AZ | Estrategia DR Propuesta |
| --------------- | ------- | --------- | -------------- | -------- | --------------------- | ---------- | ------------------------- |
| | RDS/Aurora/DynamoDB/ElastiCache | | |
| | | | |

### Replicación

- [ ] ¿Se usa Aurora Global Database actualmente? Si no, ¿se puede implementar?
- [ ] ¿Se usan RDS Cross-Region Read Replicas actualmente?
- [ ] ¿Se usan DynamoDB Global Tables actualmente?
- [ ] ¿Se usa ElastiCache Global Datastore actualmente?
- [ ] ¿Cuál es el lag de replicación aceptable para cada base de datos?
- [ ] ¿Se ha medido el lag de replicación actual entre regiones?

### Respaldos

- [ ] ¿Se usa AWS Backup para respaldos centralizados?
- [ ] ¿Los respaldos se copian a us-west-2 actualmente?
- [ ] ¿Cuál es la retención de respaldos actual?
- [ ] ¿Se ha probado restaurar un respaldo en us-west-2?
- [ ] ¿Cuánto tiempo toma restaurar la base de datos más grande desde un snapshot?

### Failover de Base de Datos

- [ ] ¿Se ha probado un failover de Aurora Global Database?
- [ ] ¿Cuánto tiempo tomó el failover en la prueba?
- [ ] ¿Se ha probado promover un RDS Read Replica?
- [ ] ¿Las aplicaciones pueden reconectarse automáticamente después de un failover?
- [ ] ¿Se necesita cambiar connection strings durante el failover o se usa un endpoint DNS?
- [ ] ¿Hay datos que se generan localmente y no se replican? (ej. tablas temporales, caché)

---

## Equipo de Ciberseguridad

### Seguridad en la Región de DR

- [ ] ¿Se requiere que la región de DR cumpla con los mismos estándares de seguridad que la primaria?
- [ ] ¿Los security groups y NACLs se replicarán idénticamente en us-west-2?
- [ ] ¿Se usa AWS WAF? ¿Las reglas se aplicarán en ambas regiones?
- [ ] ¿Se usa AWS Shield Advanced? ¿Está habilitado en ambas regiones?
- [ ] ¿Se usa AWS GuardDuty? ¿Está habilitado en us-west-2?
- [ ] ¿Se usa AWS Config? ¿Las reglas se aplicarán en us-west-2?

### Gestión de Secretos y Llaves

- [ ] ¿Todos los secretos en Secrets Manager se replicarán a us-west-2?
- [ ] ¿Se usarán KMS Multi-Region Keys o llaves independientes por región?
- [ ] ¿Los certificados SSL/TLS (ACM) están solicitados en ambas regiones?
- [ ] ¿Se usa algún HSM (CloudHSM)? ¿Se necesita en la región de DR?
- [ ] ¿Las llaves de encriptación de EBS, RDS y S3 son accesibles desde us-west-2?

### Auditoría y Cumplimiento

- [ ] ¿Se requiere que los logs de auditoría estén disponibles en ambas regiones?
- [ ] ¿CloudTrail está habilitado en ambas regiones?
- [ ] ¿Los logs de CloudTrail se centralizan en un bucket S3? ¿Se replica?
- [ ] ¿Se requiere que el DRP cumpla con alguna regulación específica? (LFPDPPP, PCI-DSS, SOX, ISO 22301)
- [ ] ¿Se necesita una evaluación de riesgos formal para la arquitectura de DR?
- [ ] ¿El equipo de auditoría interna necesita revisar el DRP?

### Respuesta a Incidentes

- [ ] ¿El DRP se integra con el plan de respuesta a incidentes de seguridad?
- [ ] ¿Qué pasa si el desastre es causado por un ataque de seguridad (ransomware, breach)?
- [ ] ¿Se tienen respaldos inmutables (WORM) para proteger contra ransomware?
- [ ] ¿Se usa AWS Backup Vault Lock para prevenir eliminación de respaldos?
- [ ] ¿Se tiene un procedimiento para aislar la región comprometida?

---

## Equipo de Desarrollo

### Aplicaciones y DR

- [ ] ¿Las aplicaciones están diseñadas para ser multi-región? Si no, ¿qué cambios se necesitan?
- [ ] ¿Las aplicaciones usan endpoints DNS o IPs hardcodeadas para conectarse a servicios?
- [ ] ¿Las aplicaciones pueden detectar y manejar un failover de base de datos automáticamente?
- [ ] ¿Las aplicaciones manejan reintentos (retry) con backoff exponencial?
- [ ] ¿Las aplicaciones son idempotentes? (pueden procesar el mismo mensaje/request más de una vez sin efectos secundarios)
- [ ] ¿Qué pasa con las sesiones de usuario durante un failover? ¿Se pierden?
- [ ] ¿Se usa almacenamiento de sesiones externo (Redis, DynamoDB) o en memoria?

### Estado y Datos

- [ ] ¿Las aplicaciones almacenan estado localmente (en disco, en memoria)?
- [ ] Si almacenan estado local, ¿cómo se replicará a la región de DR?
- [ ] ¿Las aplicaciones escriben archivos a disco? ¿A S3? ¿A EFS?
- [ ] ¿Hay colas de mensajes (SQS) con mensajes en vuelo que se perderían en un failover?
- [ ] ¿Hay procesos batch o cron jobs que deben ejecutarse en la región de DR?
- [ ] ¿Cómo se manejarán las transacciones en vuelo durante el failover?

### CI/CD

- [ ] ¿El pipeline de CI/CD despliega a ambas regiones?
- [ ] Si no, ¿cuánto esfuerzo se requiere para habilitarlo?
- [ ] ¿Se usan CloudFormation StackSets, CDK, o Terraform para despliegue multi-región?
- [ ] ¿Las variables de ambiente y configuración son específicas por región?
- [ ] ¿El pipeline puede desplegar solo a la región de DR si es necesario?

### Feature Flags y Configuración

- [ ] ¿Se usan feature flags? ¿El servicio de feature flags tiene DR?
- [ ] ¿Se usa AWS AppConfig, Parameter Store, o algún servicio de configuración?
- [ ] ¿La configuración se replica automáticamente a us-west-2?

---

## Equipo de QA / Pruebas

### Pruebas de DR

- [ ] ¿Se ha definido un plan de pruebas específico para DR?
- [ ] ¿Se tienen pruebas automatizadas que se puedan ejecutar contra la región de DR?
- [ ] ¿Se pueden ejecutar pruebas de humo (smoke tests) rápidamente después de un failover?
- [ ] ¿Cuánto tiempo toma ejecutar las pruebas de validación post-failover?
- [ ] ¿Se tienen scripts para validar integridad de datos después del failover?

### Criterios de Éxito

- [ ] ¿Cuáles son los criterios para declarar un failover exitoso?
- [ ] ¿Cuáles son los criterios para declarar un failback exitoso?
- [ ] ¿Se medirá el RTO y RPO real durante las pruebas?
- [ ] ¿Quién firma la aceptación de las pruebas de DR?

### Simulacros

- [ ] ¿Con qué frecuencia se realizarán simulacros de DR? (recomendado: trimestral)
- [ ] ¿Se realizarán simulacros de escritorio (tabletop) además de pruebas técnicas?
- [ ] ¿Se usará AWS Fault Injection Service (FIS) para inyectar fallas controladas?
- [ ] ¿Se tiene un ambiente de staging donde probar el failover antes de producción?

---

## Equipo de Operaciones / SRE

### Monitoreo y Alertas

- [ ] ¿Se tienen dashboards de CloudWatch que muestren métricas de ambas regiones?
- [ ] ¿Se tienen alarmas configuradas para detectar fallas en la región primaria?
- [ ] ¿Cuáles métricas dispararían una evaluación de failover?

| Métrica | Umbral para Evaluar Failover | Umbral para Ejecutar Failover |
| --------- | ------------------------------ | ------------------------------- |
| Disponibilidad de la aplicación | |
| Latencia P99 | |
| Tasa de errores 5xx | |
| Health check de Route 53 | |
| Replicación lag de Aurora | |
| CPU de instancias EC2/RDS | |

- [ ] ¿Se usa CloudWatch cross-region observability?
- [ ] ¿Se tienen alarmas compuestas (composite alarms) para correlacionar múltiples señales?
- [ ] ¿Las alertas llegan por múltiples canales? (email, SMS, Slack, PagerDuty)

### Runbooks y Automatización

- [ ] ¿Se tiene un runbook documentado para el proceso de failover?
- [ ] ¿El runbook ha sido probado y validado?
- [ ] ¿Cuántos pasos del failover están automatizados vs manuales?
- [ ] ¿Se usa AWS Systems Manager Automation para orquestar el failover?
- [ ] ¿Se tiene un runbook para el proceso de failback?
- [ ] ¿Se tiene un runbook para escenarios parciales? (ej. solo falla la base de datos, solo falla el cómputo)

### Operación en DR

- [ ] ¿El equipo de operaciones tiene acceso a la consola de AWS en us-west-2?
- [ ] ¿Se tienen las mismas herramientas de operación disponibles en la región de DR?
- [ ] ¿Los logs de la región de DR se centralizan en el mismo lugar que los de la primaria?
- [ ] ¿Se tiene acceso SSH/SSM a las instancias en la región de DR?
- [ ] ¿Hay personal disponible 24/7 para ejecutar un failover de emergencia?
- [ ] ¿Se tiene un canal de comunicación de emergencia que no dependa de la región primaria?

### Mantenimiento del DRP

- [ ] ¿Quién es responsable de mantener actualizado el DRP?
- [ ] ¿Se actualizará el DRP cada vez que haya un cambio en la arquitectura?
- [ ] ¿Se tiene un proceso para verificar que la región de DR está sincronizada con la primaria?
- [ ] ¿Se monitorea el lag de replicación de todos los servicios continuamente?
- [ ] ¿Se tienen alertas si la replicación se detiene o el lag excede el RPO?

---

## Equipo de Soporte / Mesa de Ayuda

### Comunicación con Usuarios

- [ ] ¿El equipo de soporte sabe que existe un DRP y cuál es su rol durante un desastre?
- [ ] ¿Se tiene un script de comunicación para informar a usuarios internos durante un failover?
- [ ] ¿Se tiene un script de comunicación para informar a clientes externos?
- [ ] ¿Se tiene una página de estatus (status page) que se actualice durante incidentes?
- [ ] ¿La página de estatus está hospedada fuera de la región primaria?
- [ ] ¿El sistema de tickets de soporte tiene DR? ¿Seguirá funcionando durante un failover?

---

## Instrucciones para Responder

1. Cada equipo debe designar un responsable para recopilar las respuestas
2. Las respuestas deben ser lo más específicas posible — evitar "sí/no" sin contexto
3. Si no se conoce la respuesta, indicar **"Por investigar"** con fecha compromiso
4. Priorizar las preguntas de los servicios Tier 1 (críticos)
5. Agendar una sesión de revisión conjunta una vez que todos los equipos hayan respondido
6. Las respuestas alimentarán directamente el diseño del DRP

| Equipo | Responsable | Fecha de entrega | Estado |
| -------- | ------------- | ------------------- | -------- |
| Gestión / Management | | Pendiente |
| Arquitectura | | Pendiente |
| Infraestructura | | Pendiente |
| Base de Datos | | Pendiente |
| Ciberseguridad | | Pendiente |
| Desarrollo | | Pendiente |
| QA / Pruebas | | Pendiente |
| Operaciones / SRE | | Pendiente |
| Soporte / Mesa de Ayuda | | Pendiente |
