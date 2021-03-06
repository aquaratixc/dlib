/*
Copyright (c) 2019 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.concurrency.threadpool;

import dlib.core.memory;
import dlib.concurrency.workerthread;
import dlib.concurrency.taskqueue;

class ThreadPool
{
    uint maxThreads;
    WorkerThread[] workerThreads;
    Task[] tasks;
    TaskQueue taskQueue;
    bool running = true;

    this(uint maxThreads)
    {
        this.maxThreads = maxThreads;
        workerThreads = New!(WorkerThread[])(maxThreads);
        tasks = New!(Task[])(maxThreads);

        taskQueue = New!TaskQueue();

        foreach(i, ref t; workerThreads)
        {
            t = New!WorkerThread(i, this);
            t.start();
        }
    }

    ~this()
    {
        running = false;
        foreach(i, ref t; workerThreads)
        {
            t.join();
            Delete(t);
        }
        Delete(taskQueue);
        Delete(workerThreads);
        Delete(tasks);
    }

    void update()
    {
        if (taskQueue.tasks.length == 0)
            return;

        foreach(i, t; workerThreads)
        {
            if (!t.busy)
            {
                t.busy = true;
                Task inputTask = taskQueue.dequeue();
                tasks[i] = inputTask;
                tasks[i].state = TaskState.Pending;
                break;
            }
        }
    }

    void submit(void delegate() taskFunc)
    {
        Task task = Task(TaskState.Idle, taskFunc);
        if (!taskQueue.enqueue(task))
        {
            task.state = TaskState.Pending;
            task.state = TaskState.Running;
            task.func();
            task.state = TaskState.Complete;
        }
    }

    bool tasksDone()
    {
        if (taskQueue.tasks.length == 0)
        {
            foreach(i, t; workerThreads)
            {
                if (t.busy)
                    return false;
            }

            return true;
        }
        else
            return false;
    }
}
