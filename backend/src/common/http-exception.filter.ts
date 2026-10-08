import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Response } from 'express';

const DEFAULT_CODES: Record<number, [string, string]> = {
  400: ['BAD_REQUEST', 'The request is not valid.'],
  401: ['UNAUTHORIZED', 'Please log in to continue.'],
  403: ['FORBIDDEN', 'You do not have access to this page.'],
  404: ['NOT_FOUND', 'Not found.'],
  429: ['TOO_MANY_REQUESTS', 'Too many requests. Please try again in a while.'],
};

/** Turns every error into the standard { error: { code, message } } body. */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'object' && body !== null && 'error' in body && typeof body.error === 'object') {
        res.status(status).json(body);
        return;
      }
      const [code, message] = DEFAULT_CODES[status] ?? ['ERROR', exception.message];
      res.status(status).json({ error: { code, message } });
      return;
    }

    this.logger.error(exception instanceof Error ? exception.stack : String(exception));
    res
      .status(HttpStatus.INTERNAL_SERVER_ERROR)
      .json({ error: { code: 'INTERNAL_ERROR', message: 'Something went wrong. Please try again.' } });
  }
}
