# Module 09: NestJS Architecture — Dependency Injection, Modules & Request Pipelines

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Enterprise Frameworks, Dependency Injection & Modular Architecture

---

## 1. The NestJS Enterprise Architectural Paradigm

While Express and Fastify are unopinionated micro-frameworks, **NestJS** is an enterprise-grade, opinionated application framework written in TypeScript.

It combines object-oriented programming (OOP), functional programming (FP), and functional reactive programming (FRP) with an Angular-inspired **Hierarchical Dependency Injection (DI)** container:

```text
┌─────────────────────────────────────────────────────────────┐
│                 NestJS Core Architectural Layers            │
├────────────────────┬────────────────────────────────────────┤
│ **`@Module()`**    │ Encapsulates a domain boundary         │
│                    │ (declares controllers, services, DI).  │
├────────────────────┼────────────────────────────────────────┤
│ **`@Controller()`**│ Handles HTTP requests and parameter    │
│                    │ mapping (`@Get()`, `@Post()`, `@Body`).│
├────────────────────┼────────────────────────────────────────┤
│ **`@Injectable()`**│ Business logic services injected via   │
│                    │ constructor Dependency Injection.      │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. The NestJS Request Lifecycle Pipeline

Every incoming request travels through a strict, multi-stage processing pipeline:

```text
Incoming Request
       │
       ▼
[1. Global & Route Middleware] (Raw request mutation)
       │
       ▼
[2. Guards (`canActivate`)] (Authentication & RBAC checks)
       │
       ▼
[3. Interceptors (Pre-Controller)] (Telemetry, caching, execution timing)
       │
       ▼
[4. Pipes (`transform`)] (Type conversion & class-validator DTO validation)
       │
       ▼
[5. Controller Handler Method] (Executes business logic in Service)
       │
       ▼
[6. Interceptors (Post-Controller)] (Response transformation & envelope shaping)
       │
       ▼
[7. Exception Filters (`@Catch`)] (Catches unhandled errors into JSON responses)
```

---

## 3. Dependency Injection & Service Providers

```typescript
// src/users/users.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';

export interface UserEntity {
  id: string;
  name: string;
  email: string;
  role: string;
}

@Injectable()
export class UsersService {
  private readonly users: Map<String, UserEntity> = new Map([
    ['u_1', { id: 'u_1', name: 'Alice Chen', email: 'alice@acme.com', role: 'admin' }],
  ]);

  async findById(id: string): Promise<UserEntity> {
    const user = this.users.get(id);
    if (!user) {
      throw new NotFoundException(`User with ID ${id} does not exist`);
    }
    return user;
  }

  async create(userDto: Omit<UserEntity, 'id'>): Promise<UserEntity> {
    const id = `u_${Date.now()}`;
    const newUser: UserEntity = { id, ...userDto };
    this.users.set(id, newUser);
    return newUser;
  }
}
```

---

## 4. DTO Validation with Pipes (`class-validator`)

```typescript
// src/users/dto/create-user.dto.ts
import { IsEmail, IsString, MinLength, IsIn } from 'class-validator';

export class CreateUserDto {
  @IsString()
  @MinLength(2, { message: 'Name must have at least 2 characters' })
  name!: string;

  @IsEmail({}, { message: 'Must be a valid corporate email' })
  email!: string;

  @IsIn(['admin', 'member'], { message: 'Role must be admin or member' })
  role!: string;
}
```

---

## 5. Controller Architecture with Guards & Interceptors

```typescript
// src/users/users.controller.ts
import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  UseInterceptors,
  HttpStatus,
  HttpCode,
} from '@nestjs/common';
import { UsersService, UserEntity } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';
import { AuthGuard } from '../common/guards/auth.guard';
import { LoggingInterceptor } from '../common/interceptors/logging.interceptor';

@Controller('users')
@UseGuards(AuthGuard) // ◄── Applies auth guard to all endpoints in controller!
@UseInterceptors(LoggingInterceptor)
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get(':id')
  async getUser(@Param('id') id: string): Promise<UserEntity> {
    return this.usersService.findById(id);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createUser(@Body() createUserDto: CreateUserDto): Promise<UserEntity> {
    return this.usersService.create(createUserDto);
  }
}
```

---

## 6. Asynchronous Custom Dynamic Providers (`useFactory`)

When a service depends on an asynchronous connection (e.g. Redis connection pool or PostgreSQL pool):

```typescript
// src/database/database.module.ts
import { Module, Global } from '@nestjs/common';

export const REDIS_CLIENT = 'REDIS_CLIENT';

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      useFactory: async () => {
        console.log('Connecting to Redis cluster asynchronously...');
        // Simulating async connection:
        await new Promise((r) => setTimeout(r, 200));
        return { isConnected: true, host: 'redis.cluster.internal' };
      },
    },
  ],
  exports: [REDIS_CLIENT],
})
export class DatabaseModule {}
```

---

## 7. Root Application Module (`src/app.module.ts`)

```typescript
// src/app.module.ts
import { Module, ValidationPipe } from '@nestjs/common';
import { APP_PIPE } from '@nestjs/core';
import { UsersModule } from './users/users.module';
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [DatabaseModule, UsersModule],
  providers: [
    // Global validation pipe across entire microservice:
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        whitelist: true,       // Automatically strips non-whitelisted properties
        forbidNonWhitelisted: true, // Throws error if extra fields sent
        transform: true,       // Auto-transforms payloads to DTO instances
      }),
    },
  ],
})
export class AppModule {}
```

---

## Troubleshooting & Best Practices

1. **`Nest can't resolve dependencies of the Service` Error**
   This is the most common NestJS error. It means a service injected in constructor `A` belongs to Module `B`, but Module `B` forgot to add the service to its **`exports: [ServiceB]`** array, or Module `A` forgot to add `imports: [ModuleB]`.

2. **Circular Dependencies Solution (`forwardRef`)**
   If Module A imports Module B and Module B imports Module A, use `forwardRef(() => ModuleB)` in both imports arrays and `@Inject(forwardRef(() => ServiceB))` in service constructors.
