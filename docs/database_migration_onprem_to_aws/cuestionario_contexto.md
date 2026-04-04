# Cuestionario de Contexto: Migración de Base de Datos On-Premises a AWS

Este documento contiene las preguntas que cada equipo debe responder antes de iniciar el plan de migración. Las respuestas proporcionarán el contexto necesario para diseñar una migración exitosa con el menor riesgo posible.

!!! warning "Importante"
    Todas las preguntas deben ser respondidas **antes** de iniciar la Fase 1 (Descubrimiento y Evaluación). Las respuestas incompletas incrementan el riesgo de fallas durante la migración.

---

## Equipo de Base de Datos (DBA)

### Inventario de Bases de Datos

- [ ] ¿Cuántas bases de datos están en alcance para la migración?
- [ ] Para cada base de datos, proporcionar:

| Atributo | Respuesta |
|----------|-----------|
| Nombre de la base de datos | |
| Motor y versión exacta (ej. SQL Server 2019 Enterprise SP2) | |
| Tamaño total (datos + índices + logs) en GB/TB | |
| Número de esquemas | |
| Número de tablas | |
| Número de vistas | |
| Número de stored procedures | |
| Número de funciones | |
| Número de triggers | |
| Número de jobs programados (SQL Agent, cron, etc.) | |
| Collation / Character Set | |
| ¿Usa encriptación TDE (Transparent Data Encryption)? | |
| ¿Usa encriptación a nivel de columna? | |
| ¿Tiene tablas con columnas LOB (TEXT, IMAGE, BLOB, CLOB)? ¿Cuántas? | |
| Tamaño promedio y máximo de los LOBs | |
| ¿Tiene tablas sin llave primaria? ¿Cuáles? | |
| ¿Usa linked servers o cross-database queries? ¿A dónde apuntan? | |
| ¿Tiene replicación configurada (Always On, Log Shipping, etc.)? | |
| ¿Usa particionamiento de tablas? ¿En cuáles tablas? | |

### Rendimiento y Carga

- [ ] ¿Cuál es el volumen promedio de transacciones por segundo (TPS) en horario pico?
- [ ] ¿Cuál es el horario de mayor carga (día y hora)?
- [ ] ¿Cuál es el horario de menor carga (ventana ideal para migración)?
- [ ] ¿Existen procesos batch o ETL que se ejecutan en horarios específicos? ¿Cuáles y cuándo?
- [ ] ¿Cuál es el crecimiento mensual/anual de datos en GB?
- [ ] ¿Cuáles son las queries más críticas y de mayor consumo de recursos?
- [ ] ¿Cuál es el uso promedio de CPU, memoria e IOPS del servidor actual?

### Alta Disponibilidad y Respaldos

- [ ] ¿Cuál es la estrategia actual de respaldos (full, diferencial, log)?
- [ ] ¿Con qué frecuencia se toman respaldos?
- [ ] ¿Dónde se almacenan los respaldos actualmente?
- [ ] ¿Cuánto tiempo se retienen los respaldos?
- [ ] ¿Se ha probado la restauración de respaldos recientemente? ¿Cuándo fue la última vez?
- [ ] ¿Cuál es el RPO actual (pérdida máxima de datos aceptable)?
- [ ] ¿Cuál es el RTO actual (tiempo máximo de inactividad aceptable)?
- [ ] ¿Existe un plan de recuperación ante desastres actualmente? ¿Está documentado?

### Dependencias y Conectividad

- [ ] ¿Qué aplicaciones se conectan a esta base de datos? Listar todas.
- [ ] ¿Qué connection strings se usan actualmente? (sin contraseñas)
- [ ] ¿Se conectan aplicaciones externas (de terceros o socios) a la base de datos?
- [ ] ¿Existen integraciones con otras bases de datos (ETL, replicación, linked servers)?
- [ ] ¿Se usa algún ORM o framework de acceso a datos? ¿Cuál?
- [ ] ¿Hay procedimientos almacenados que llaman a servicios externos (web services, correo, etc.)?

---

## Equipo de Desarrollo

### Aplicaciones

- [ ] ¿Cuántas aplicaciones se conectan a las bases de datos en alcance?
- [ ] Para cada aplicación:

| Atributo | Respuesta |
|----------|-----------|
| Nombre de la aplicación | |
| Lenguaje de programación / Framework | |
| ¿Es aplicación web, API, servicio, batch, desktop? | |
| ¿Dónde está desplegada actualmente? (on-premises, EC2, ECS, Lambda) | |
| ¿Usa connection pooling? ¿Qué librería? | |
| ¿El connection string está hardcodeado o en configuración? | |
| ¿Usa un ORM? ¿Cuál? (Entity Framework, Hibernate, SQLAlchemy, etc.) | |
| ¿Tiene queries SQL nativas (raw SQL) además del ORM? | |
| ¿Usa features específicos del motor? (ej. T-SQL, PL/SQL, extensiones) | |
| ¿Tiene pruebas automatizadas? ¿Qué porcentaje de cobertura? | |
| ¿Tiene pipeline de CI/CD? ¿Qué herramienta? | |

### Compatibilidad

- [ ] Si la migración es heterogénea (ej. SQL Server → PostgreSQL):
    - [ ] ¿La aplicación usa sintaxis SQL específica del motor actual? (ej. `TOP`, `NOLOCK`, `@@IDENTITY`, `GETDATE()`)
    - [ ] ¿Usa tipos de datos específicos del motor? (ej. `UNIQUEIDENTIFIER`, `HIERARCHYID`, `SQL_VARIANT`)
    - [ ] ¿Usa stored procedures con lógica de negocio compleja?
    - [ ] ¿Cuánto esfuerzo estiman para adaptar el código de la aplicación?
    - [ ] ¿Tienen capacidad para hacer pruebas de regresión completas?

### Manejo de Errores y Resiliencia

- [ ] ¿La aplicación maneja reconexión automática si la base de datos se reinicia?
- [ ] ¿La aplicación maneja timeouts de conexión correctamente?
- [ ] ¿Tiene circuit breakers o retry logic implementado?
- [ ] ¿Qué pasa si la base de datos no está disponible por 5 minutos? ¿Y por 30 minutos?
- [ ] ¿La aplicación puede funcionar en modo de solo lectura temporalmente?

### Datos Sensibles

- [ ] ¿La aplicación maneja datos personales (PII)? ¿Cuáles campos?
- [ ] ¿La aplicación maneja datos financieros o de tarjetas de crédito (PCI)?
- [ ] ¿La aplicación maneja datos de salud (HIPAA)?
- [ ] ¿Existen requisitos regulatorios sobre dónde pueden residir los datos?

---

## Equipo de Infraestructura

### Ambiente Actual

- [ ] ¿Cuáles son las especificaciones del servidor de base de datos actual?

| Atributo | Respuesta |
|----------|-----------|
| CPU (cores/vCPUs) | |
| Memoria RAM (GB) | |
| Almacenamiento (tipo, tamaño, IOPS) | |
| Sistema operativo y versión | |
| ¿Es servidor físico o virtual? | |
| ¿Está en un clúster? ¿Qué tipo? | |

- [ ] ¿Cuál es la utilización promedio de CPU, memoria y disco?
- [ ] ¿Cuál es la utilización pico de CPU, memoria y disco?

### Red y Conectividad

- [ ] ¿Existe conectividad VPN o Direct Connect entre on-premises y AWS?
- [ ] Si existe, ¿cuál es el ancho de banda disponible?
- [ ] ¿Cuál es la latencia actual entre on-premises y la región de AWS destino?
- [ ] ¿Hay restricciones de firewall que bloqueen puertos de base de datos (1433, 3306, 5432, 1521)?
- [ ] ¿Se puede abrir conectividad temporal para la migración?
- [ ] ¿Cuál es la IP pública o rango de IPs del data center on-premises?
- [ ] ¿Existe un proxy o balanceador entre las aplicaciones y la base de datos?

### AWS Actual

- [ ] ¿Ya tienen cuenta(s) de AWS? ¿Cuántas?
- [ ] ¿Usan AWS Organizations?
- [ ] ¿Tienen VPCs existentes en la región destino?
- [ ] ¿Cuál es el esquema de direccionamiento IP en AWS (CIDRs)?
- [ ] ¿Tienen subnets privadas disponibles para RDS/Aurora?
- [ ] ¿Tienen experiencia previa con AWS DMS?
- [ ] ¿Tienen experiencia previa con Amazon RDS o Aurora?

### DNS y Balanceo

- [ ] ¿Cómo resuelven las aplicaciones el nombre del servidor de base de datos? (IP fija, DNS interno, alias CNAME)
- [ ] ¿Pueden cambiar el DNS o connection string de las aplicaciones durante el cutover?
- [ ] ¿Cuánto tiempo toma un cambio de DNS en propagarse en su ambiente?

---

## Equipo de Ciberseguridad

### Acceso y Autenticación

- [ ] ¿Cómo se autentican los usuarios y aplicaciones a la base de datos? (SQL auth, Windows auth, IAM, certificados)
- [ ] ¿Cuántos usuarios/logins tienen acceso a la base de datos?
- [ ] ¿Existen cuentas de servicio? ¿Cuáles y para qué aplicaciones?
- [ ] ¿Se usa Active Directory para autenticación de base de datos?
- [ ] ¿Tienen un sistema de gestión de secretos? (Vault, Secrets Manager, etc.)
- [ ] ¿Con qué frecuencia se rotan las contraseñas de base de datos?

### Encriptación

- [ ] ¿Los datos están encriptados en reposo actualmente? ¿Con qué mecanismo?
- [ ] ¿Los datos están encriptados en tránsito (SSL/TLS)? ¿Es obligatorio?
- [ ] ¿Se requiere encriptación en reposo en el destino? ¿Con qué estándar?
- [ ] ¿Tienen llaves de encriptación propias (BYOK) o usan las del proveedor?
- [ ] ¿Necesitan control sobre las llaves KMS en AWS?

### Cumplimiento y Regulación

- [ ] ¿Qué regulaciones aplican? (LFPDPPP, PCI-DSS, SOX, HIPAA, ISO 27001, etc.)
- [ ] ¿Existen restricciones sobre en qué país/región pueden residir los datos?
- [ ] ¿Se requiere auditoría de acceso a la base de datos? ¿Qué herramienta usan?
- [ ] ¿Se requiere enmascaramiento de datos en ambientes no productivos?
- [ ] ¿Tienen un proceso de evaluación de riesgos para migraciones a la nube?
- [ ] ¿Se requiere una evaluación de impacto de privacidad (PIA)?

### Seguridad de Red

- [ ] ¿La base de datos debe ser accesible solo desde redes privadas?
- [ ] ¿Se requiere segmentación de red específica?
- [ ] ¿Usan WAF, IDS/IPS o algún sistema de detección de intrusos?
- [ ] ¿Tienen requisitos de logging y retención de logs de seguridad?
- [ ] ¿Cuánto tiempo deben retener los logs de auditoría?

---

## Equipo de Gestión / Management

### Negocio y Prioridades

- [ ] ¿Cuál es la justificación de negocio para la migración? (costo, rendimiento, modernización, fin de soporte)
- [ ] ¿Cuál es la fecha límite para completar la migración? ¿Es flexible?
- [ ] ¿Cuál es el presupuesto aprobado para la migración?
- [ ] ¿Cuál es el costo mensual actual de la infraestructura on-premises?
- [ ] ¿Cuál es el costo mensual esperado en AWS?
- [ ] ¿Hay licencias de software que se pueden reutilizar (BYOL) o que expiran?

### Impacto y Riesgo

- [ ] ¿Cuál es el impacto al negocio si la base de datos no está disponible por 1 hora? ¿Y por 4 horas?
- [ ] ¿Cuál es el costo estimado por hora de inactividad?
- [ ] ¿Cuál es la ventana de mantenimiento aprobada para el cutover? (día, hora, duración)
- [ ] ¿Se puede hacer el cutover en fin de semana?
- [ ] ¿Hay fechas bloqueadas donde NO se puede migrar? (cierre fiscal, eventos, temporada alta)
- [ ] ¿Quién es el responsable de dar la aprobación final (go/no-go) para el cutover?
- [ ] ¿Quién es el responsable de decidir un rollback?

### Comunicación

- [ ] ¿Quiénes son los stakeholders que deben ser notificados antes, durante y después de la migración?
- [ ] ¿Cuál es el plan de comunicación? (canales, frecuencia, escalación)
- [ ] ¿Se necesita notificar a clientes externos sobre una ventana de mantenimiento?
- [ ] ¿Existe un proceso de gestión de cambios (change management) que se deba seguir?

### Equipo y Capacitación

- [ ] ¿El equipo de DBA tiene experiencia con el motor de base de datos destino?
- [ ] ¿Se requiere capacitación antes de la migración? ¿En qué temas?
- [ ] ¿Hay personal disponible para soporte 24/7 durante el cutover?
- [ ] ¿Se contratará soporte externo (AWS Professional Services, partner)?

---

## Equipo de QA / Pruebas

### Estrategia de Pruebas

- [ ] ¿Existe un ambiente de pruebas donde se pueda validar la migración antes de producción?
- [ ] ¿Tienen un conjunto de pruebas de regresión automatizadas?
- [ ] ¿Cuánto tiempo toma ejecutar el suite completo de pruebas?
- [ ] ¿Tienen datos de prueba representativos o usan una copia de producción?
- [ ] ¿Pueden ejecutar pruebas de carga/estrés contra la base de datos destino?

### Criterios de Aceptación

- [ ] ¿Cuáles son los criterios para considerar la migración exitosa?
- [ ] ¿Qué queries o reportes críticos deben validarse después de la migración?
- [ ] ¿Cuál es el rendimiento mínimo aceptable? (latencia, TPS)
- [ ] ¿Quién firma la aceptación de las pruebas?
- [ ] ¿Cuánto tiempo de validación se necesita después del cutover antes de declarar éxito?

---

## Equipo de Operaciones / SRE

### Monitoreo

- [ ] ¿Qué herramientas de monitoreo usan actualmente? (Datadog, Grafana, Nagios, Zabbix, CloudWatch)
- [ ] ¿Qué métricas de base de datos monitorean actualmente?
- [ ] ¿Tienen alertas configuradas? ¿Cuáles son los umbrales?
- [ ] ¿Quién recibe las alertas? ¿Hay rotación de guardia (on-call)?
- [ ] ¿Tienen dashboards existentes que necesiten actualizarse?

### Operación Día a Día

- [ ] ¿Quién será responsable de operar la base de datos en AWS después de la migración?
- [ ] ¿Tienen runbooks documentados para operaciones comunes? (reinicio, failover, respaldo manual, escalamiento)
- [ ] ¿Tienen un proceso de gestión de incidentes?
- [ ] ¿Cómo manejan los parches y actualizaciones de la base de datos actualmente?
- [ ] ¿Con qué frecuencia aplican parches?

### Rollback

- [ ] ¿Cuál es el plan de rollback si la migración falla?
- [ ] ¿Cuánto tiempo puede estar la base de datos fuente sin recibir escrituras durante el cutover?
- [ ] ¿Se puede mantener la base de datos fuente en línea como fallback por cuántos días?
- [ ] ¿Quién decide cuándo descomisionar la base de datos fuente?

---

## Equipo de Arquitectura

### Decisiones de Diseño

- [ ] ¿Se ha decidido si la migración es homogénea (mismo motor) o heterogénea (cambio de motor)?
- [ ] Si es heterogénea, ¿cuál es el motor destino y por qué?
- [ ] ¿Se usará Amazon RDS o Amazon Aurora? ¿Por qué?
- [ ] ¿Se requiere Multi-AZ para alta disponibilidad?
- [ ] ¿Se requiere réplicas de lectura para distribuir carga?
- [ ] ¿Cuál es la clase de instancia recomendada? (basado en métricas actuales)
- [ ] ¿Cuál es el tipo de almacenamiento recomendado? (gp3, io1, io2)
- [ ] ¿Se necesita un plan de Disaster Recovery multi-región?

### Integración

- [ ] ¿Cómo se integrará la base de datos migrada con otros servicios de AWS? (Lambda, ECS, etc.)
- [ ] ¿Se usará AWS Secrets Manager para las credenciales?
- [ ] ¿Se usará IAM authentication para la base de datos?
- [ ] ¿Se necesita acceso desde múltiples VPCs o cuentas de AWS?
- [ ] ¿Se requiere conectividad híbrida permanente (on-premises + AWS) después de la migración?

---

## Instrucciones para Responder

1. Cada equipo debe designar un responsable para recopilar las respuestas
2. Las respuestas deben ser lo más específicas posible (evitar "sí/no" sin contexto)
3. Si no se conoce la respuesta, indicar "Por investigar" con fecha compromiso
4. Agendar una sesión de revisión conjunta una vez que todos los equipos hayan respondido
5. Las respuestas alimentarán directamente el plan de implementación de la migración

| Equipo | Responsable | Fecha de entrega | Estado |
|--------|-------------|-------------------|--------|
| Base de Datos | | | Pendiente |
| Desarrollo | | | Pendiente |
| Infraestructura | | | Pendiente |
| Ciberseguridad | | | Pendiente |
| Gestión | | | Pendiente |
| QA / Pruebas | | | Pendiente |
| Operaciones / SRE | | | Pendiente |
| Arquitectura | | | Pendiente |
